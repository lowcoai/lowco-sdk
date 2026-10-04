from __future__ import annotations

import asyncio
import inspect
import json
import logging
import math
import secrets
import time
from collections.abc import Awaitable, Callable, Iterable, Mapping
from typing import Any, NamedTuple, TypeVar, cast

from typing_extensions import Self
from websockets.asyncio.client import connect as _websockets_connect
from websockets.exceptions import ConnectionClosed

from ._errors import FluxError, FluxUnauthorizedError
from ._utils import build_websocket_url, generate_client_id, normalize_topic
from .types import (
    ALL_EVENTS,
    CHANNEL_HEALTH_CHECK,
    CHANNEL_SUBSCRIPTION,
    ChannelEventHandler,
    ConnectFactory,
    ConnectionState,
    ErrorHandler,
    FluxConnection,
    MessageData,
    MessageHandler,
    MessageType,
    SocketEvent,
    SocketMessage,
    StateHandler,
    SubscriptionSpec,
    TokenProvider,
    TopicSubscription,
)

logger = logging.getLogger("lowcoai.flux")

DEFAULT_HEARTBEAT_INTERVAL = 5.0
DEFAULT_RECONNECT_INTERVAL = 1.0
MAX_RECONNECT_INTERVAL = 30.0

# The event the server answers a ping with (``SocketEvent.PONG`` is the
# request-side name and is not what arrives).
_PONG_REPLY = "pong"

# The server upgrades the socket before it checks the token. A rejected token
# then gets an ``Unauthorized`` frame on ``flux:error`` and a close with 1008
# (policy violation); either one marks the socket as rejected.
_CHANNEL_ERROR = "flux:error"
_EVENT_UNAUTHORIZED = "Unauthorized"
_CLOSE_POLICY_VIOLATION = 1008

_H = TypeVar("_H")


async def _default_connect(url: str) -> FluxConnection:
    # No frame size cap, like a browser WebSocket (websockets defaults to 1 MiB).
    return await _websockets_connect(url, max_size=None)


class FluxClient:
    """asyncio client for the flux realtime service.

    One instance owns a single connection to ``wss://ws.lowco.ai/``,
    reconnects with exponential backoff, and replays every subscription
    (event filters included) on each reconnect.

    ``connect()`` returns immediately; a background task dials, reads and
    reconnects until ``disconnect()``. Use ``async with FluxClient(...)`` to
    tie the connection to a block.

    ``token_provider`` (plain or ``async``) is asked for the token before
    every connection attempt. When the server rejects a token the client
    reports ``FluxUnauthorizedError`` and reconnects only with a different
    one: it stops until ``set_token()`` or ``connect()`` instead of retrying
    the same token.
    """

    def __init__(
        self,
        token: str,
        org_id: str,
        *,
        client_id: str | None = None,
        heartbeat_interval: float = DEFAULT_HEARTBEAT_INTERVAL,
        reconnect_interval: float = DEFAULT_RECONNECT_INTERVAL,
        query_params: Mapping[str, str] | None = None,
        connect: ConnectFactory | None = None,
        token_provider: TokenProvider | None = None,
    ) -> None:
        if not isinstance(token, str) or not token.strip():
            raise FluxError("token is required")
        if not isinstance(org_id, str) or not org_id.strip():
            raise FluxError("org_id is required")
        if not heartbeat_interval > 0:
            raise FluxError("heartbeat_interval must be a positive number of seconds")
        if not reconnect_interval > 0:
            raise FluxError("reconnect_interval must be a positive number of seconds")

        self._token = token
        self._org_id = org_id
        self._client_id = client_id or generate_client_id()
        self._heartbeat_interval = float(heartbeat_interval)
        self._reconnect_interval = float(reconnect_interval)
        self._query_params = dict(query_params or {})
        self._connect_factory: ConnectFactory = connect or _default_connect
        self._token_provider = token_provider

        self._ws: FluxConnection | None = None
        self._connected = False
        self._manually_closed = False
        self._ping_seq = 1
        self._last_sent_seq: int | None = None
        # Reset by the first expected pong, never by an open: the server opens
        # the socket before it checks the token.
        self._reconnect_attempt = 0
        self._supervisor: asyncio.Task[None] | None = None
        self._in_backoff = False
        # The token the server rejected, while the client waits for another.
        self._rejected_token: str | None = None
        # Ends a backoff early, or a wait after a rejected token.
        self._wake = asyncio.Event()
        self._connected_event = asyncio.Event()
        # Held across every subscription change *and* the frame reporting it,
        # and across the replay on open, so the wire order always matches the
        # order of changes (a replay can never resurrect a released topic).
        self._sub_lock = asyncio.Lock()

        # What this client wants delivered: topic -> event patterns (``*`` =
        # every event), insertion-ordered. It is the client's own record, not
        # a mirror of server acks, so a reconnect replays it in full and a
        # subscribe made while the socket is down is sent on the next open.
        self._desired: dict[str, dict[str, None]] = {}

        self._message_handlers: dict[MessageHandler, None] = {}
        self._error_handlers: dict[ErrorHandler, None] = {}
        self._state_handlers: dict[StateHandler, None] = {}
        self._channel_handlers: dict[str, dict[str, dict[ChannelEventHandler, None]]] = {}
        self._channels: dict[str, FluxChannel] = {}
        self._tasks: set[asyncio.Future[Any]] = set()

    def __repr__(self) -> str:
        return (
            f"FluxClient(org_id={self._org_id!r}, client_id={self._client_id!r}, "
            f"connected={self._connected!r})"
        )

    @property
    def client_id(self) -> str:
        """The ``cli`` id sent on every connection."""
        return self._client_id

    # --- lifecycle ---------------------------------------------------------

    async def connect(self) -> None:
        """Start connecting in the background and return immediately.

        A no-op while the client is already connected or connecting; while it
        is waiting to reconnect, it skips the rest of the backoff, and after
        a rejected token it tries again right away.
        """
        self._manually_closed = False
        supervisor = self._supervisor
        if supervisor is not None and not supervisor.done():
            if self._in_backoff or self._rejected_token is not None:
                self._wake.set()
            return
        task = asyncio.create_task(self._supervise(), name=f"flux-{self._client_id}")
        task.add_done_callback(_log_supervisor_crash)
        self._supervisor = task

    async def disconnect(self) -> None:
        """Close the socket and stop reconnecting. Subscriptions and handlers
        are kept, so a later ``connect()`` replays them."""
        self._manually_closed = True
        task, self._supervisor = self._supervisor, None
        if task is None or task.done():
            return
        task.cancel()
        await asyncio.wait({task})

    def set_token(self, token: str) -> None:
        """Use ``token`` from the next connection attempt on (a blank one is
        ignored). An open socket is kept.

        A client stopped by a rejected token reconnects right away when
        ``token`` differs from the rejected one, unless ``disconnect()`` was
        called.
        """
        if not isinstance(token, str) or not token.strip():
            return
        self._token = token
        rejected = self._rejected_token
        if rejected is not None and token != rejected and not self._manually_closed:
            self._wake.set()

    def is_connected(self) -> bool:
        """``True`` from the ``"connected"`` state until the socket closes."""
        return self._connected

    async def wait_until_connected(self, timeout: float | None = None) -> None:
        """Wait for the socket to open.

        Raises ``TimeoutError`` after ``timeout`` seconds, and ``FluxError``
        when ``connect()`` has not been called or ``disconnect()`` is called
        while waiting.
        """
        if self._connected:
            return
        supervisor = self._supervisor
        if supervisor is None or supervisor.done():
            raise FluxError("client is not connecting; call connect() first")
        waiter = asyncio.ensure_future(self._connected_event.wait())
        pending: set[asyncio.Future[Any]] = {waiter, supervisor}
        try:
            done, _ = await asyncio.wait(
                pending, timeout=timeout, return_when=asyncio.FIRST_COMPLETED
            )
        finally:
            waiter.cancel()
        if waiter in done:
            return
        if supervisor.done():
            raise FluxError("client was disconnected before it connected")
        raise TimeoutError(f"flux: not connected after {timeout} seconds")

    async def __aenter__(self) -> Self:
        await self.connect()
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        await self.disconnect()

    # --- subscriptions -----------------------------------------------------

    async def subscribe(self, topic: str, *, events: Iterable[str] | None = None) -> FluxChannel:
        """Ask the server for a topic's events and return a handle for it.

        Pass ``events`` to receive only the matching ones
        (``subscribe("channel:<schema>", events=["messages.*"])``) or omit it
        for every event. Subscribes add to what the client already holds on a
        topic; only the difference goes over the wire. While the socket is
        down the subscription is kept and sent on the next open.
        """
        parsed = _parse_one(topic, events)
        if parsed is None:
            raise FluxError("at least one topic is required to subscribe")
        await self._add_subscriptions([parsed])
        return self._get_or_create_channel(parsed.topic)

    async def subscribe_many(self, specs: Iterable[SubscriptionSpec]) -> None:
        """Subscribe to a batch of topics in one frame. Each entry is a bare
        topic (every event) or ``{"topic": ..., "events": [...]}``."""
        parsed = _parse_specs(specs)
        if not parsed:
            raise FluxError("at least one topic is required to subscribe")
        await self._add_subscriptions(parsed)

    async def unsubscribe(self, topic: str) -> None:
        """Drop a topic whole and remove the channel's bound handlers."""
        parsed = _parse_one(topic, None)
        if parsed is None:
            raise FluxError("at least one topic is required to unsubscribe")
        self._channel_handlers.pop(parsed.topic, None)
        self._channels.pop(parsed.topic, None)
        await self._remove_subscriptions([parsed])

    async def unsubscribe_many(self, specs: Iterable[SubscriptionSpec]) -> None:
        """Stop receiving events. A bare topic drops it whole; a topic with
        ``events`` drops only those patterns, and the topic once none is
        left. Bound handlers are kept."""
        parsed = _parse_specs(specs)
        if not parsed:
            raise FluxError("at least one topic is required to unsubscribe")
        await self._remove_subscriptions(parsed)

    def get_subscribed_topics(self) -> list[str]:
        """The topics this client holds (and replays on every reconnect)."""
        return list(self._desired)

    def get_subscriptions(self) -> list[TopicSubscription]:
        """Every held topic with the event patterns asked of it."""
        return [{"topic": topic, "events": list(held)} for topic, held in self._desired.items()]

    async def send_message(self, channel: str, event: str, data: MessageData) -> None:
        """Send an ``action`` frame. Raises ``FluxError`` when the socket is
        not open (messages are not queued)."""
        await self._send(channel, event, data)

    # --- handlers ----------------------------------------------------------

    def on_message(self, handler: MessageHandler) -> Callable[[], None]:
        """Call ``handler`` for every received frame. Returns a remover."""
        return _register(self._message_handlers, handler)

    def on_error(self, handler: ErrorHandler) -> Callable[[], None]:
        """Call ``handler`` for transient socket errors. Returns a remover."""
        return _register(self._error_handlers, handler)

    def on_state(self, handler: StateHandler) -> Callable[[], None]:
        """Call ``handler`` on ``"connected"`` / ``"disconnected"`` /
        ``"error"``. Returns a remover."""
        return _register(self._state_handlers, handler)

    def bind(self, channel: str, event: str, handler: ChannelEventHandler) -> Callable[[], None]:
        """Call ``handler(data, message)`` for frames whose trimmed channel and
        event equal these. Returns a function that removes this binding."""
        ch = normalize_topic(channel)
        ev = normalize_topic(event)
        if not ch:
            raise FluxError("channel is required")
        if not ev:
            raise FluxError("event is required")
        self._channel_handlers.setdefault(ch, {}).setdefault(ev, {})[handler] = None

        def unbind() -> None:
            self.unbind(ch, ev, handler)

        return unbind

    def unbind(
        self,
        channel: str,
        event: str | None = None,
        handler: ChannelEventHandler | None = None,
    ) -> None:
        """Remove bindings: every handler of a channel, of one event, or one
        handler of one event."""
        ch = normalize_topic(channel)
        if not ch:
            raise FluxError("channel is required")
        by_event = self._channel_handlers.get(ch)
        if by_event is None:
            return
        if not event:
            del self._channel_handlers[ch]
            return
        ev = normalize_topic(event)
        if not ev:
            return
        handlers = by_event.get(ev)
        if handlers is None:
            return
        if handler is None:
            del by_event[ev]
        else:
            handlers.pop(handler, None)
            if not handlers:
                del by_event[ev]
        if not by_event:
            del self._channel_handlers[ch]

    # --- connection supervisor ---------------------------------------------

    def _url(self, token: str) -> str:
        # replay=1 tells the server this client re-sends every subscription on
        # connect, so it starts the socket clean.
        params = {**self._query_params, "replay": "1"}
        return build_websocket_url(token, self._org_id, self._client_id, params)

    async def _supervise(self) -> None:
        # Resolved ahead of a dial only after a rejection, to decide whether
        # the next dial is worth making; otherwise resolved just before it.
        token: str | None = None
        while not self._manually_closed:
            if token is None:
                token = await self._resolve_token()
            rejected = await self._run_connection(token)
            if self._manually_closed:
                return
            if not rejected:
                token = None
                await self._backoff()
                continue
            # The same token would only be rejected again: wait for another
            # instead of redialing it on a timer.
            rejected_token, token = token, await self._resolve_token()
            if token == rejected_token:
                token = None
                await self._park(rejected_token)
            else:
                await self._backoff()

    async def _resolve_token(self) -> str:
        """The provider's token when it returns one, else the current token.
        A provider token becomes the current one (the fallback next time)."""
        provider = self._token_provider
        if provider is None:
            return self._token
        try:
            result = provider()
            if inspect.isawaitable(result):
                result = await result
        except Exception as exc:
            self._emit_error(exc)
            return self._token
        if isinstance(result, str) and result.strip():
            self._token = result
        return self._token

    async def _park(self, rejected_token: str) -> None:
        # No timer: only set_token() with another token, connect() or
        # disconnect() (which cancels this task) ends the wait.
        self._wake.clear()
        self._rejected_token = rejected_token
        try:
            await self._wake.wait()
        finally:
            self._rejected_token = None

    async def _backoff(self) -> None:
        # The exponent is capped only to keep the float finite; the delay
        # itself is capped at MAX_RECONNECT_INTERVAL.
        exponent = min(self._reconnect_attempt, 64)
        delay = min(self._reconnect_interval * 2.0**exponent, MAX_RECONNECT_INTERVAL)
        self._reconnect_attempt += 1
        self._wake.clear()
        self._in_backoff = True
        try:
            await asyncio.wait_for(self._wake.wait(), timeout=delay)
        except asyncio.TimeoutError:
            pass
        finally:
            self._in_backoff = False

    async def _run_connection(self, token: str) -> bool:
        """Dial with ``token`` and read until the socket closes. ``True`` when
        the server rejected the token."""
        try:
            ws = await self._connect_factory(self._url(token))
        except Exception as exc:  # a failed dial counts as a close: back off
            self._emit_state("error")
            self._emit_error(exc)
            self._emit_state("disconnected")
            return False

        heartbeat: asyncio.Task[None] | None = None
        try:
            async with self._sub_lock:
                self._ws = ws
                self._connected = True
                self._connected_event.set()
                self._emit_state("connected")
                await self._send_first_ping(ws)
                heartbeat = asyncio.create_task(self._heartbeat(ws))
                await self._replay(ws)
            return await self._read(ws)
        finally:
            if self._ws is ws:
                self._ws = None
                self._connected = False
                self._connected_event.clear()
            if heartbeat is not None:
                heartbeat.cancel()
            self._emit_state("disconnected")
            await _close_quietly(ws)
            if heartbeat is not None:
                await asyncio.wait({heartbeat})

    async def _read(self, ws: FluxConnection) -> bool:
        """Read until the socket closes. ``True`` when the server rejected the
        token (an ``Unauthorized`` error frame or a 1008 close)."""
        try:
            async for frame in ws:
                error = self._handle_frame(frame)
                if error is None:
                    continue
                rejected = isinstance(error, FluxUnauthorizedError)
                if rejected:
                    self._emit_state("error")
                self._emit_error(error)
                await _close_quietly(ws)
                return rejected
        except Exception as exc:  # abnormal closure or transport failure
            self._emit_state("error")
            if _close_code(exc) == _CLOSE_POLICY_VIOLATION:
                unauthorized = FluxUnauthorizedError()
                unauthorized.__cause__ = exc
                self._emit_error(unauthorized)
                return True
            self._emit_error(exc)
        return False

    def _handle_frame(self, frame: str | bytes) -> FluxError | None:
        """Dispatch one frame. Returns why the socket must be dropped: a pong
        out of sync, or the server rejecting the token."""
        text = frame if isinstance(frame, str) else bytes(frame).decode("utf-8", "replace")
        try:
            payload = json.loads(text)
        except ValueError:
            self._emit_error(FluxError(f"received non-JSON message: {text}"))
            return None
        if not isinstance(payload, dict):
            self._emit_error(FluxError(f"received non-object message: {text}"))
            return None
        message = cast(SocketMessage, payload)
        if message.get("event") == _PONG_REPLY:
            if not self._is_expected_pong(message.get("data")):
                return FluxError("pong out of sync, reconnecting")
            # A matching pong proves the socket healthy (token accepted,
            # server answering), so only now does the backoff start over.
            self._reconnect_attempt = 0
        self._emit_channel_event(message)
        self._emit_message(message)
        if (
            normalize_topic(message.get("channel")) == _CHANNEL_ERROR
            and normalize_topic(message.get("event")) == _EVENT_UNAUTHORIZED
        ):
            return FluxUnauthorizedError()
        return None

    # --- heartbeat ---------------------------------------------------------

    async def _send_first_ping(self, ws: FluxConnection) -> None:
        # Same sequence as the TypeScript client: the first ping on a socket
        # carries the current counter, which then restarts at 1.
        seq = self._ping_seq
        self._last_sent_seq = seq
        self._ping_seq = 1
        await self._send_ping(ws, seq)

    async def _heartbeat(self, ws: FluxConnection) -> None:
        while True:
            await asyncio.sleep(self._heartbeat_interval)
            seq = self._ping_seq
            self._last_sent_seq = seq
            self._ping_seq = seq + 1
            if not await self._send_ping(ws, seq):
                return

    async def _send_ping(self, ws: FluxConnection, seq: int) -> bool:
        try:
            await self._write(ws, CHANNEL_HEALTH_CHECK, SocketEvent.PING, str(seq))
        except ConnectionClosed:
            return False  # the read loop reports the closure
        except Exception as exc:
            self._emit_error(exc)
            await _close_quietly(ws)  # replace a socket that cannot ping
            return False
        return True

    def _is_expected_pong(self, content: Any) -> bool:
        last = self._last_sent_seq
        if last is None or isinstance(content, bool):
            return False
        if not isinstance(content, (int, float, str)):
            return False
        try:
            seq = float(content)
        except (ValueError, OverflowError):
            return False
        return math.isfinite(seq) and seq == last

    # --- sending -----------------------------------------------------------

    async def _write(
        self,
        ws: FluxConnection,
        channel: str,
        event: str,
        data: MessageData,
        type: MessageType = "action",
    ) -> None:
        message: SocketMessage = {
            "channel": channel,
            "type": type,
            "event": event,
            "data": data,
            "timestamp": int(time.time()),
            "request_id": secrets.token_hex(10),
        }
        await ws.send(json.dumps(message, separators=(",", ":")))

    async def _send(
        self, channel: str, event: str, data: MessageData, type: MessageType = "action"
    ) -> None:
        ws = self._ws
        if ws is None or not self._connected:
            raise FluxError("websocket is not connected")
        try:
            await self._write(ws, channel, event, data, type)
        except ConnectionClosed as exc:
            raise FluxError("websocket is not connected") from exc

    async def _write_subscriptions(
        self, ws: FluxConnection, event: str, entries: list[SubscriptionSpec]
    ) -> None:
        try:
            await self._write(ws, CHANNEL_SUBSCRIPTION, event, entries)
        except ConnectionClosed:
            # Closed in flight: the server drops a socket's subscriptions with
            # it and the next open replays what is desired.
            pass
        except Exception as exc:
            self._emit_error(exc)

    async def _replay(self, ws: FluxConnection) -> None:
        """A new socket holds nothing server-side: replay everything wanted."""
        entries = [_to_wire(topic, list(held)) for topic, held in self._desired.items()]
        if entries:
            await self._write_subscriptions(ws, SocketEvent.SUBSCRIBE, entries)

    async def _add_subscriptions(self, specs: list[_ParsedSpec]) -> None:
        async with self._sub_lock:
            added: list[SubscriptionSpec] = []
            for spec in specs:
                held = self._desired.setdefault(spec.topic, {})
                fresh = [e for e in (spec.events or [ALL_EVENTS]) if e not in held]
                held.update(dict.fromkeys(fresh))
                if fresh:
                    added.append(_to_wire(spec.topic, fresh))
            ws = self._ws
            if added and ws is not None and self._connected:
                await self._write_subscriptions(ws, SocketEvent.SUBSCRIBE, added)

    async def _remove_subscriptions(self, specs: list[_ParsedSpec]) -> None:
        async with self._sub_lock:
            removed: list[SubscriptionSpec] = []
            for spec in specs:
                if spec.events is None:
                    self._desired.pop(spec.topic, None)
                    removed.append(spec.topic)
                    continue
                held = self._desired.get(spec.topic)
                if held is None:
                    continue
                dropped = [e for e in spec.events if e in held]
                for e in dropped:
                    del held[e]
                if not held:
                    # Released whole, so the server drops the topic whatever it holds.
                    del self._desired[spec.topic]
                    removed.append(spec.topic)
                elif dropped:
                    removed.append({"topic": spec.topic, "events": dropped})
            # A closed socket has nothing to tell: the server drops a
            # connection's subscriptions with it, and the next open replays
            # only what is left.
            ws = self._ws
            if removed and ws is not None and self._connected:
                await self._write_subscriptions(ws, SocketEvent.UNSUBSCRIBE, removed)

    # --- dispatch ----------------------------------------------------------

    def _emit_message(self, message: SocketMessage) -> None:
        for handler in list(self._message_handlers):
            self._invoke(handler, message)

    def _emit_state(self, state: ConnectionState) -> None:
        for handler in list(self._state_handlers):
            self._invoke(handler, state)

    def _emit_error(self, error: Exception) -> None:
        handlers = list(self._error_handlers)
        if not handlers:
            logger.debug("flux error: %r", error)
            return
        for handler in handlers:
            self._invoke(handler, error, from_error_handler=True)

    def _emit_channel_event(self, message: SocketMessage) -> None:
        channel = normalize_topic(message.get("channel"))
        event = normalize_topic(message.get("event"))
        if not channel or not event:
            return
        handlers = self._channel_handlers.get(channel, {}).get(event)
        if not handlers:
            return
        data = message.get("data")
        for handler in list(handlers):
            self._invoke(handler, data, message)

    def _invoke(
        self,
        handler: Callable[..., Awaitable[None] | None],
        *args: Any,
        from_error_handler: bool = False,
    ) -> None:
        """Run a handler without letting it break the read loop. A returned
        awaitable is scheduled as a task (and kept referenced until done)."""
        try:
            result = handler(*args)
        except Exception as exc:
            self._handler_failed(exc, from_error_handler)
            return
        if inspect.isawaitable(result):
            task = asyncio.ensure_future(result)
            self._tasks.add(task)
            task.add_done_callback(lambda done: self._handler_task_done(done, from_error_handler))

    def _handler_task_done(self, task: asyncio.Future[Any], from_error_handler: bool) -> None:
        self._tasks.discard(task)
        if task.cancelled():
            return
        exc = task.exception()
        if isinstance(exc, Exception):
            self._handler_failed(exc, from_error_handler)
        elif exc is not None:
            logger.error("flux handler raised", exc_info=exc)

    def _handler_failed(self, exc: Exception, from_error_handler: bool) -> None:
        # A failing handler is reported to the error handlers; one that fails
        # itself (or no error handler at all) is logged instead.
        if from_error_handler or not self._error_handlers:
            logger.error("flux handler raised", exc_info=exc)
            return
        self._emit_error(exc)

    # --- channels ----------------------------------------------------------

    def _get_or_create_channel(self, name: str) -> FluxChannel:
        channel = self._channels.get(name)
        if channel is None:
            channel = FluxChannel(self, name)
            self._channels[name] = channel
        return channel


class FluxChannel:
    """Convenience handle for one topic, returned by ``FluxClient.subscribe``."""

    def __init__(self, client: FluxClient, name: str) -> None:
        self._client = client
        self._name = name

    def __repr__(self) -> str:
        return f"FluxChannel({self._name!r})"

    @property
    def name(self) -> str:
        return self._name

    def bind(self, event: str, handler: ChannelEventHandler) -> Callable[[], None]:
        return self._client.bind(self._name, event, handler)

    def unbind(self, event: str | None = None, handler: ChannelEventHandler | None = None) -> None:
        self._client.unbind(self._name, event, handler)

    async def unsubscribe(self) -> None:
        await self._client.unsubscribe(self._name)

    async def destroy(self) -> None:
        """Remove every bound handler and unsubscribe."""
        self._client.unbind(self._name)
        await self._client.unsubscribe(self._name)

    async def send_message(self, event: str, data: MessageData) -> None:
        await self._client.send_message(self._name, event, data)


# --- helpers ---------------------------------------------------------------


class _ParsedSpec(NamedTuple):
    topic: str
    # None for a bare topic: every event on subscribe, the whole topic on
    # unsubscribe.
    events: list[str] | None


def _parse_one(topic: Any, events: Any) -> _ParsedSpec | None:
    name = normalize_topic(topic)
    if not name:
        return None
    if isinstance(events, str):
        events = [events]
    patterns: dict[str, None] = {}
    for event in events or ():
        pattern = normalize_topic(event)
        if pattern:
            patterns[pattern] = None
    return _ParsedSpec(name, list(patterns) or None)


def _parse_specs(specs: Iterable[SubscriptionSpec]) -> list[_ParsedSpec]:
    if isinstance(specs, str):
        specs = [specs]
    out: list[_ParsedSpec] = []
    for spec in specs:
        if isinstance(spec, str):
            parsed = _parse_one(spec, None)
        elif isinstance(spec, Mapping):
            parsed = _parse_one(spec.get("topic"), spec.get("events"))
        else:
            parsed = None
        if parsed is not None:
            out.append(parsed)
    return out


def _to_wire(topic: str, events: list[str]) -> SubscriptionSpec:
    """A bare topic when it wants every event (the frame older servers read)."""
    if not events or (len(events) == 1 and events[0] == ALL_EVENTS):
        return topic
    return {"topic": topic, "events": list(events)}


def _register(registry: dict[_H, None], handler: _H) -> Callable[[], None]:
    registry[handler] = None

    def remove() -> None:
        registry.pop(handler, None)

    return remove


def _close_code(exc: Exception) -> int | None:
    """The close code the server sent, when ``exc`` is a websockets closure."""
    if not isinstance(exc, ConnectionClosed):
        return None
    # websockets >= 10 carries the received Close frame as ``rcvd`` (``None``
    # when none arrived) and deprecates ``code`` since 13.1; ``code`` is only
    # read where ``rcvd`` does not exist.
    if hasattr(exc, "rcvd"):
        return exc.rcvd.code if exc.rcvd is not None else None
    code = getattr(exc, "code", None)
    return code if isinstance(code, int) else None


async def _close_quietly(ws: FluxConnection) -> None:
    try:
        await ws.close()
    except Exception:
        logger.debug("flux: error while closing the socket", exc_info=True)


def _log_supervisor_crash(task: asyncio.Task[None]) -> None:
    if not task.cancelled() and task.exception() is not None:
        logger.error("flux connection loop crashed", exc_info=task.exception())
