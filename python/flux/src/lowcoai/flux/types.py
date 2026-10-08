"""Wire and handler types for the flux realtime service.

Frames are ``TypedDict``s whose keys match the JSON on the wire
(``request_id``, ``run_id`` are snake_case there). Fields are optional unless
marked ``Required``.
"""

from collections.abc import AsyncIterator, Awaitable, Callable
from typing import Any, Final, Literal, Protocol, TypeAlias

from typing_extensions import Required, TypedDict

__all__ = [
    "ALL_EVENTS",
    "CHANNEL_HEALTH_CHECK",
    "CHANNEL_SUBSCRIPTION",
    "ChannelEventHandler",
    "ConnectFactory",
    "ConnectionState",
    "ErrorHandler",
    "FluxConnection",
    "MessageData",
    "MessageHandler",
    "MessageMeta",
    "MessageType",
    "SocketEvent",
    "SocketMessage",
    "StateHandler",
    "SubscriptionSpec",
    "TokenProvider",
    "TopicSubscription",
]

MessageData: TypeAlias = Any
"""Any JSON value."""

MessageType = Literal["action", "event", "system", "error", "ack"]

ConnectionState = Literal["connected", "disconnected", "error"]


class MessageMeta(TypedDict, total=False):
    seq: int
    run_id: str


class SocketMessage(TypedDict, total=False):
    """The JSON envelope exchanged with the flux server."""

    type: MessageType
    channel: str
    event: str
    data: MessageData
    request_id: str
    timestamp: int
    """Unix time in seconds."""
    meta: MessageMeta


class SocketEvent:
    """Reserved wire-level event names (the TS ``SocketEvent`` enum)."""

    PING: Final = "pi"
    PONG: Final = "po"
    SUBSCRIBE: Final = "sb"
    UNSUBSCRIBE: Final = "usb"
    MESSAGE: Final = "m"
    REPLY: Final = "reply"


CHANNEL_SUBSCRIPTION: Final = "flux:subscription"
"""Channel that carries ``sb`` / ``usb`` frames."""

CHANNEL_HEALTH_CHECK: Final = "flux:health_check"
"""Channel that carries heartbeat pings."""

ALL_EVENTS: Final = "*"
"""The event pattern that matches every event on a topic."""


class TopicSubscription(TypedDict, total=False):
    """A topic, narrowed to the events wanted from it.

    The server delivers only events matching one of the patterns: ``*`` alone
    is every event, otherwise patterns are compared token by token on ``.``
    with ``*`` matching exactly one token (``messages.*``, ``*.delete``,
    ``messages.insert``). Omitted or empty ``events`` means every event
    (subscribe) or the whole topic (unsubscribe).
    """

    topic: Required[str]
    events: list[str]


SubscriptionSpec: TypeAlias = str | TopicSubscription
"""A bare topic string (every event) or a topic with an event filter."""

# Handlers may be plain functions or coroutine functions; a returned awaitable
# is scheduled as a task on the running loop.
MessageHandler: TypeAlias = Callable[[SocketMessage], Awaitable[None] | None]
ErrorHandler: TypeAlias = Callable[[Exception], Awaitable[None] | None]
StateHandler: TypeAlias = Callable[[ConnectionState], Awaitable[None] | None]
ChannelEventHandler: TypeAlias = Callable[[MessageData, SocketMessage], Awaitable[None] | None]
"""Called with ``(message["data"], message)``."""


class FluxConnection(Protocol):
    """The slice of a WebSocket connection the client uses.

    ``websockets.asyncio.client.ClientConnection`` satisfies it. Iteration
    yields incoming frames and ends when the connection closes (raising for an
    abnormal closure).
    """

    async def send(self, message: str) -> None: ...

    async def close(self) -> None: ...

    def __aiter__(self) -> AsyncIterator[str | bytes]: ...


ConnectFactory: TypeAlias = Callable[[str], Awaitable[FluxConnection]]
"""Opens a connection to the given ``wss://`` URL."""

TokenProvider: TypeAlias = Callable[[], str | None | Awaitable[str | None]]
"""Returns the token for the next connection attempt (plain or ``async``).
``None``, a blank string or an exception keeps the current token."""
