"""End-to-end behaviour against a local flux stub (a real WebSocket server).

The scenarios mirror ``go/flux/client_test.go``: the stub records every frame
the client sends, can reject handshakes and drop connections, and the client
is pointed at it with ``connect=`` while it keeps building its real
``wss://ws.lowco.ai/`` URL.
"""

from __future__ import annotations

import asyncio
import inspect
import json
import time
from collections.abc import AsyncIterator, Callable
from http import HTTPStatus
from typing import Any, TypeVar
from urllib.parse import parse_qs, urlsplit

import pytest
from websockets.asyncio.client import ClientConnection
from websockets.asyncio.client import connect as ws_connect
from websockets.asyncio.server import ServerConnection, serve
from websockets.exceptions import ConnectionClosed, InvalidStatus
from websockets.http11 import Request, Response

from lowcoai.flux import (
    CHANNEL_HEALTH_CHECK,
    CHANNEL_SUBSCRIPTION,
    WS_URL,
    ConnectionState,
    FluxClient,
    FluxError,
    SocketMessage,
)

T = TypeVar("T")

TIMEOUT = 5.0

# websockets >= 15 honours system proxies; never route the stub through one.
_DIAL_OPTIONS: dict[str, Any] = (
    {"proxy": None} if "proxy" in inspect.signature(ws_connect).parameters else {}
)


async def get(queue: asyncio.Queue[T]) -> T:
    return await asyncio.wait_for(queue.get(), TIMEOUT)


async def eventually(predicate: Callable[[], bool]) -> None:
    deadline = time.monotonic() + TIMEOUT
    while not predicate():
        assert time.monotonic() < deadline, "condition not met in time"
        await asyncio.sleep(0.005)


class FluxStub:
    """Accepts connections and records what the client sends."""

    def __init__(self) -> None:
        self.port = 0
        self.accepting = True
        self.echo_pongs = False
        self.dialed: list[str] = []
        self.request_paths: list[str] = []
        self.accepted: list[ServerConnection] = []
        self.connections: asyncio.Queue[ServerConnection] = asyncio.Queue()
        # (event, data) of every flux:subscription frame, across connections.
        self.subscriptions: asyncio.Queue[tuple[str, Any]] = asyncio.Queue()
        # (connection index, sequence) of every heartbeat ping.
        self.pings: asyncio.Queue[tuple[int, str]] = asyncio.Queue()
        # Every other frame, parsed.
        self.frames: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
        self.clients: list[FluxClient] = []

    def process_request(self, connection: ServerConnection, request: Request) -> Response | None:
        self.request_paths.append(request.path)
        if not self.accepting:
            return connection.respond(HTTPStatus.SERVICE_UNAVAILABLE, "down\n")
        if parse_qs(urlsplit(request.path).query).get("replay") != ["1"]:
            return connection.respond(HTTPStatus.BAD_REQUEST, "client must announce replay=1\n")
        return None

    async def handler(self, ws: ServerConnection) -> None:
        index = len(self.accepted)
        self.accepted.append(ws)
        self.connections.put_nowait(ws)
        try:
            async for raw in ws:
                frame = json.loads(raw)
                if frame.get("channel") == CHANNEL_SUBSCRIPTION:
                    self.subscriptions.put_nowait((frame["event"], frame["data"]))
                elif frame.get("channel") == CHANNEL_HEALTH_CHECK:
                    self.pings.put_nowait((index, frame["data"]))
                    if self.echo_pongs:
                        await ws.send(
                            json.dumps(
                                {
                                    "channel": CHANNEL_HEALTH_CHECK,
                                    "event": "pong",
                                    "data": frame["data"],
                                }
                            )
                        )
                else:
                    self.frames.put_nowait(frame)
        except ConnectionClosed:
            pass

    async def dial(self, url: str) -> ClientConnection:
        """The client always builds the production URL; send it here instead,
        query string and all."""
        self.dialed.append(url)
        query = urlsplit(url).query
        return await ws_connect(f"ws://127.0.0.1:{self.port}/?{query}", **_DIAL_OPTIONS)

    def client(
        self,
        *,
        heartbeat_interval: float = 60.0,
        reconnect_interval: float = 0.01,
        client_id: str | None = None,
        query_params: dict[str, str] | None = None,
    ) -> FluxClient:
        client = FluxClient(
            "tok_123",
            "org_1",
            client_id=client_id,
            heartbeat_interval=heartbeat_interval,
            reconnect_interval=reconnect_interval,
            query_params=query_params,
            connect=self.dial,
        )
        self.clients.append(client)
        return client

    async def next_connection(self) -> ServerConnection:
        return await get(self.connections)

    async def expect(self, *frames: tuple[str, Any]) -> None:
        for want in frames:
            assert await get(self.subscriptions) == want

    async def publish(self, ws: ServerConnection, message: dict[str, Any] | str | bytes) -> None:
        await ws.send(message if isinstance(message, (str, bytes)) else json.dumps(message))


@pytest.fixture
async def stub() -> AsyncIterator[FluxStub]:
    stub = FluxStub()
    async with serve(stub.handler, "127.0.0.1", 0, process_request=stub.process_request) as server:
        stub.port = server.sockets[0].getsockname()[1]
        try:
            yield stub
        finally:
            for client in stub.clients:
                await client.disconnect()


def record_states(client: FluxClient) -> asyncio.Queue[ConnectionState]:
    states: asyncio.Queue[ConnectionState] = asyncio.Queue()
    client.on_state(states.put_nowait)
    return states


def record_errors(client: FluxClient) -> asyncio.Queue[Exception]:
    errors: asyncio.Queue[Exception] = asyncio.Queue()
    client.on_error(errors.put_nowait)
    return errors


def record_messages(client: FluxClient) -> asyncio.Queue[SocketMessage]:
    messages: asyncio.Queue[SocketMessage] = asyncio.Queue()
    client.on_message(messages.put_nowait)
    return messages


async def test_url_carries_credentials_client_id_and_replay(stub: FluxStub) -> None:
    client = stub.client(client_id="cli-1", query_params={"foo": "bar baz", "replay": "0"})
    await client.connect()
    await stub.next_connection()
    await client.wait_until_connected(TIMEOUT)

    url = stub.dialed[0]
    assert url.startswith(f"{WS_URL}?")
    assert parse_qs(urlsplit(url).query) == {
        "token": ["tok_123"],
        "orgId": ["org_1"],
        "cli": ["cli-1"],
        "foo": ["bar baz"],
        "replay": ["1"],
    }
    assert parse_qs(urlsplit(stub.request_paths[0]).query)["replay"] == ["1"]


async def test_subscription_filters_and_replay(stub: FluxStub) -> None:
    client = stub.client()

    # Before the socket exists: kept, not an error, sent on connect.
    await client.subscribe_many(["agent:1", {"topic": "channel:s", "events": ["messages.*"]}])
    await client.connect()
    first = await stub.next_connection()
    await stub.expect(("sb", ["agent:1", {"topic": "channel:s", "events": ["messages.*"]}]))

    # Only the pattern the topic does not hold yet goes out.
    await client.subscribe("channel:s", events=["messages.*", "tasks.*"])
    await stub.expect(("sb", [{"topic": "channel:s", "events": ["tasks.*"]}]))

    await client.unsubscribe_many([{"topic": "channel:s", "events": ["messages.*"]}])
    await client.unsubscribe_many(["agent:1"])
    await stub.expect(
        ("usb", [{"topic": "channel:s", "events": ["messages.*"]}]),
        ("usb", ["agent:1"]),
    )

    # A dropped socket: the new one gets everything still held, filters and all.
    await first.close()
    await stub.next_connection()
    await stub.expect(("sb", [{"topic": "channel:s", "events": ["tasks.*"]}]))

    # Releasing the last pattern drops the topic whole.
    await client.unsubscribe_many([{"topic": "channel:s", "events": ["tasks.*"]}])
    await stub.expect(("usb", ["channel:s"]))
    assert client.get_subscriptions() == []


async def test_subscribe_without_events_is_bare(stub: FluxStub) -> None:
    client = stub.client()
    await client.connect()
    await stub.next_connection()
    await client.wait_until_connected(TIMEOUT)

    await client.subscribe("run:9")
    await stub.expect(("sb", ["run:9"]))
    assert client.get_subscribed_topics() == ["run:9"]


async def test_subscribe_sends_only_fresh_normalized_patterns(stub: FluxStub) -> None:
    client = stub.client()
    await client.connect()
    await client.wait_until_connected(TIMEOUT)

    await client.subscribe("  t  ", events=[" a ", "a", "", "b"])
    await stub.expect(("sb", [{"topic": "t", "events": ["a", "b"]}]))
    await client.subscribe("t", events=["b", "c"])
    await stub.expect(("sb", [{"topic": "t", "events": ["c"]}]))

    # Everything already held: no frame at all (the next frame is the next change).
    await client.subscribe("t", events=["a", "c"])
    await client.subscribe_many(["u", {"topic": "v", "events": ["*"]}, {"topic": "u"}])
    await stub.expect(("sb", ["u", "v"]))

    # Unknown patterns release nothing; a bare topic is always released.
    await client.unsubscribe_many([{"topic": "t", "events": ["zzz"]}])
    await client.unsubscribe_many([{"topic": "t", "events": ["a", "b"]}, "never-held"])
    await stub.expect(("usb", [{"topic": "t", "events": ["a", "b"]}, "never-held"]))
    assert client.get_subscriptions() == [
        {"topic": "t", "events": ["c"]},
        {"topic": "u", "events": ["*"]},
        {"topic": "v", "events": ["*"]},
    ]


async def test_unsubscribe_while_closed_sends_nothing(stub: FluxStub) -> None:
    client = stub.client()
    states = record_states(client)
    errors = record_errors(client)
    await client.subscribe_many(["x", "y"])
    await client.connect()
    first = await stub.next_connection()
    await stub.expect(("sb", ["x", "y"]))
    assert await get(states) == "connected"

    # Take the server down: the socket closes and reconnect attempts fail.
    stub.accepting = False
    await first.close()
    assert await get(states) == "disconnected"
    assert await get(states) == "error"  # a failed dial...
    dial_error = await get(errors)
    assert isinstance(dial_error, InvalidStatus)
    assert await get(states) == "disconnected"  # ...counts as a close
    assert not client.is_connected()

    # Nothing to tell a closed socket; the changes are only recorded.
    await client.unsubscribe("x")
    await client.subscribe("z", events=["a.*"])
    with pytest.raises(FluxError):
        await client.send_message("x", "e", None)

    stub.accepting = True
    await stub.next_connection()
    await stub.expect(("sb", ["y", {"topic": "z", "events": ["a.*"]}]))
    assert stub.subscriptions.empty()
    await client.wait_until_connected(TIMEOUT)


async def test_bind_dispatch_and_unbind(stub: FluxStub) -> None:
    client = stub.client()
    messages = record_messages(client)
    await client.connect()
    ws = await stub.next_connection()
    channel = await client.subscribe("runs:42")
    await stub.expect(("sb", ["runs:42"]))

    sync_calls: list[tuple[Any, SocketMessage]] = []
    async_calls: asyncio.Queue[tuple[Any, SocketMessage]] = asyncio.Queue()

    def on_status(data: Any, message: SocketMessage) -> None:
        sync_calls.append((data, message))

    async def on_status_async(data: Any, message: SocketMessage) -> None:
        await asyncio.sleep(0)
        async_calls.put_nowait((data, message))

    unbind = channel.bind("status", on_status)
    client.bind(" runs:42 ", " status ", on_status_async)  # names are trimmed

    status = {"channel": "runs:42", "event": "status", "data": {"state": "done"}}
    await stub.publish(ws, status)
    assert await get(messages) == status
    assert sync_calls == [({"state": "done"}, status)]
    assert await get(async_calls) == ({"state": "done"}, status)

    # Other events and channels only reach on_message.
    await stub.publish(ws, {"channel": "runs:42", "event": "other", "data": 1})
    await stub.publish(ws, {"channel": "runs:43", "event": "status", "data": 2})
    assert (await get(messages))["data"] == 1
    assert (await get(messages))["data"] == 2
    assert len(sync_calls) == 1

    unbind()
    await stub.publish(ws, {**status, "data": "again"})
    assert (await get(messages))["data"] == "again"
    assert len(sync_calls) == 1
    assert (await get(async_calls))[0] == "again"

    channel.unbind("status")
    await stub.publish(ws, {**status, "data": "unbound"})
    assert (await get(messages))["data"] == "unbound"
    assert async_calls.empty()

    # unsubscribe() leaves the topic and drops the channel's handlers.
    channel.bind("status", on_status)
    await channel.unsubscribe()
    await stub.expect(("usb", ["runs:42"]))
    await stub.publish(ws, {**status, "data": "after-unsubscribe"})
    assert (await get(messages))["data"] == "after-unsubscribe"
    assert len(sync_calls) == 1

    # destroy() unbinds everything and unsubscribes.
    channel = await client.subscribe("runs:42")
    await stub.expect(("sb", ["runs:42"]))
    channel.bind("status", on_status)
    await channel.destroy()
    await stub.expect(("usb", ["runs:42"]))
    await stub.publish(ws, {**status, "data": "after-destroy"})
    assert (await get(messages))["data"] == "after-destroy"
    assert len(sync_calls) == 1


async def test_handler_errors_are_reported_and_reading_continues(stub: FluxStub) -> None:
    client = stub.client()
    errors = record_errors(client)
    messages = record_messages(client)
    await client.connect()
    ws = await stub.next_connection()
    await client.wait_until_connected(TIMEOUT)

    def broken(data: Any, message: SocketMessage) -> None:
        raise RuntimeError("sync boom")

    async def broken_async(message: SocketMessage) -> None:
        raise ValueError("async boom")

    client.bind("c", "e", broken)
    client.on_message(broken_async)

    await stub.publish(ws, {"channel": "c", "event": "e", "data": 1})
    await stub.publish(ws, {"channel": "c", "event": "next", "data": 2})
    assert (await get(messages))["data"] == 1
    assert (await get(messages))["data"] == 2
    reported = {str(error) for error in [await get(errors) for _ in range(3)]}
    assert reported == {"sync boom", "async boom"}
    assert client.is_connected()


async def test_non_json_and_binary_frames(stub: FluxStub) -> None:
    client = stub.client()
    errors = record_errors(client)
    messages = record_messages(client)
    await client.connect()
    ws = await stub.next_connection()
    await client.wait_until_connected(TIMEOUT)

    await stub.publish(ws, "not json")
    error = await get(errors)
    assert isinstance(error, FluxError)
    assert error.message == "received non-JSON message: not json"

    await stub.publish(ws, "[1, 2]")
    error = await get(errors)
    assert "non-object" in str(error)

    await stub.publish(ws, json.dumps({"channel": "c", "event": "e", "data": "bin"}).encode())
    assert (await get(messages))["data"] == "bin"
    assert client.is_connected()
    assert len(stub.accepted) == 1


async def test_pong_mismatch_triggers_reconnect(stub: FluxStub) -> None:
    client = stub.client()
    states = record_states(client)
    errors = record_errors(client)
    messages = record_messages(client)
    await client.subscribe("run:1", events=["status"])
    await client.connect()
    first = await stub.next_connection()
    assert await get(stub.pings) == (0, "1")
    await stub.expect(("sb", [{"topic": "run:1", "events": ["status"]}]))
    assert await get(states) == "connected"

    # The expected pong (string or number) is an ordinary message.
    await stub.publish(first, {"channel": CHANNEL_HEALTH_CHECK, "event": "pong", "data": 1})
    await stub.publish(first, {"channel": CHANNEL_HEALTH_CHECK, "event": "pong", "data": "1"})
    assert (await get(messages))["data"] == 1
    assert (await get(messages))["data"] == "1"
    assert errors.empty()

    await stub.publish(first, {"channel": CHANNEL_HEALTH_CHECK, "event": "pong", "data": "999"})
    error = await get(errors)
    assert isinstance(error, FluxError)
    assert error.message == "pong out of sync, reconnecting"
    assert await get(states) == "disconnected"

    second = await stub.next_connection()
    assert second is not first
    await stub.expect(("sb", [{"topic": "run:1", "events": ["status"]}]))
    assert await get(states) == "connected"
    assert messages.empty()  # the mismatched pong was not dispatched


async def test_abnormal_close_reports_error_and_reconnects(stub: FluxStub) -> None:
    client = stub.client()
    states = record_states(client)
    errors = record_errors(client)
    await client.subscribe("a")
    await client.connect()
    first = await stub.next_connection()
    await stub.expect(("sb", ["a"]))
    assert await get(states) == "connected"

    first.transport.abort()  # no closing handshake
    assert await get(states) == "error"
    error = await get(errors)
    assert isinstance(error, ConnectionClosed)
    assert await get(states) == "disconnected"
    await stub.next_connection()
    await stub.expect(("sb", ["a"]))
    assert await get(states) == "connected"


async def test_heartbeat_sequence(stub: FluxStub) -> None:
    stub.echo_pongs = True  # matching pongs must never trigger a reconnect
    client = stub.client(heartbeat_interval=0.15)
    errors = record_errors(client)
    await client.connect()
    first = await stub.next_connection()

    # On open the current counter is sent and restarts at 1; each tick then
    # sends the counter and increments it.
    assert [await get(stub.pings) for _ in range(3)] == [(0, "1"), (0, "1"), (0, "2")]
    await first.close()

    # The next socket opens with the counter where it stood (3), then restarts.
    await stub.next_connection()
    assert [await get(stub.pings) for _ in range(2)] == [(1, "3"), (1, "1")]
    assert errors.empty()
    assert len(stub.accepted) == 2


async def test_send_message_frames(stub: FluxStub) -> None:
    client = stub.client()
    await client.connect()
    await stub.next_connection()
    await client.wait_until_connected(TIMEOUT)

    before = int(time.time())
    await client.send_message("tables:leads", "ping", {"hello": "world"})
    frame = await get(stub.frames)
    assert set(frame) == {"channel", "type", "event", "data", "timestamp", "request_id"}
    assert frame["channel"] == "tables:leads"
    assert frame["type"] == "action"
    assert frame["event"] == "ping"
    assert frame["data"] == {"hello": "world"}
    assert isinstance(frame["timestamp"], int)
    assert before <= frame["timestamp"] <= int(time.time())
    assert isinstance(frame["request_id"], str) and frame["request_id"]

    channel = await client.subscribe("runs:1")
    await channel.send_message("status", [1, 2])
    frame = await get(stub.frames)
    assert (frame["channel"], frame["event"], frame["data"]) == ("runs:1", "status", [1, 2])

    await client.disconnect()
    with pytest.raises(FluxError, match="websocket is not connected"):
        await client.send_message("tables:leads", "ping", None)


async def test_context_manager_and_disconnect_stop_reconnecting(stub: FluxStub) -> None:
    client = stub.client()
    states = record_states(client)
    async with client as flux:
        assert flux is client
        await stub.next_connection()
        await flux.wait_until_connected(TIMEOUT)
        assert flux.is_connected()
        await flux.connect()  # already connected: no second socket
        assert await get(states) == "connected"
    assert await get(states) == "disconnected"
    assert not client.is_connected()

    # No reconnect after a manual disconnect (the backoff here is 10 ms).
    await asyncio.sleep(0.1)
    assert len(stub.accepted) == 1
    assert states.empty()

    # connect() again replays what is still held.
    await client.subscribe("kept")
    await client.connect()
    await stub.next_connection()
    await stub.expect(("sb", ["kept"]))


async def test_wait_until_connected_timeout_and_disconnect(stub: FluxStub) -> None:
    stub.accepting = False
    client = stub.client(reconnect_interval=0.05)
    await client.connect()
    with pytest.raises(TimeoutError):
        await client.wait_until_connected(timeout=0.05)

    waiter = asyncio.ensure_future(client.wait_until_connected())
    await eventually(lambda: len(stub.request_paths) >= 2)
    await client.disconnect()
    with pytest.raises(FluxError, match="disconnected"):
        await waiter


async def test_connect_during_backoff_dials_right_away(stub: FluxStub) -> None:
    stub.accepting = False
    client = stub.client(reconnect_interval=30.0)
    states = record_states(client)
    await client.connect()
    assert await get(states) == "error"
    assert await get(states) == "disconnected"  # now waiting 30 s

    stub.accepting = True
    await eventually(lambda: client._in_backoff)
    await client.connect()
    await stub.next_connection()
    assert await get(states) == "connected"
