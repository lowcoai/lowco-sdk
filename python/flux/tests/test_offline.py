"""Behaviour that needs no socket: options, URL building, bookkeeping."""

from __future__ import annotations

import uuid
from typing import Any
from urllib.parse import parse_qs, urlsplit

import pytest

import lowcoai.flux as flux
from lowcoai.flux import (
    ALL_EVENTS,
    WS_URL,
    FluxClient,
    FluxError,
    FluxUnauthorizedError,
    SocketEvent,
    SocketMessage,
    build_websocket_url,
    generate_client_id,
)


def make_client(**kwargs: Any) -> FluxClient:
    return FluxClient("tok_123", "org_1", **kwargs)


def test_public_surface() -> None:
    assert flux.__version__ == "0.1.0"
    for name in flux.__all__:
        assert hasattr(flux, name), name
    assert WS_URL == "wss://api.lowco.ai/v1/ws"
    assert ALL_EVENTS == "*"
    assert (
        SocketEvent.PING,
        SocketEvent.PONG,
        SocketEvent.SUBSCRIBE,
        SocketEvent.UNSUBSCRIBE,
        SocketEvent.MESSAGE,
        SocketEvent.REPLY,
    ) == ("pi", "po", "sb", "usb", "m", "reply")


def test_build_websocket_url() -> None:
    url = build_websocket_url("t o/k", "org_1", "cli-1", {"foo": "bar", "token": "override"})
    assert url.startswith(f"{WS_URL}?")
    # Keys keep their position; a query param replaces an existing key.
    assert urlsplit(url).query == "token=override&orgId=org_1&cli=cli-1&foo=bar"
    assert parse_qs(urlsplit(build_websocket_url("t o/k", "o", "c")).query) == {
        "token": ["t o/k"],
        "orgId": ["o"],
        "cli": ["c"],
    }


def test_generate_client_id_is_a_uuid4() -> None:
    first, second = generate_client_id(), generate_client_id()
    assert uuid.UUID(first).version == 4
    assert first != second


@pytest.mark.parametrize(
    ("token", "org_id", "message"),
    [
        ("", "org_1", "token is required"),
        ("   ", "org_1", "token is required"),
        ("tok", "", "org_id is required"),
        ("tok", " ", "org_id is required"),
    ],
)
def test_constructor_requires_token_and_org(token: str, org_id: str, message: str) -> None:
    with pytest.raises(FluxError, match=message):
        FluxClient(token, org_id)


def test_constructor_rejects_non_positive_intervals() -> None:
    with pytest.raises(FluxError):
        make_client(heartbeat_interval=0)
    with pytest.raises(FluxError):
        make_client(reconnect_interval=-1)


def test_unauthorized_error() -> None:
    error = FluxUnauthorizedError()
    assert isinstance(error, FluxError)
    assert error.message == "the server rejected the token (unauthorized)"
    assert repr(error) == "FluxUnauthorizedError('the server rejected the token (unauthorized)')"
    assert repr(FluxError("x")) == "FluxError('x')"


def test_set_token_replaces_the_token_and_ignores_blanks() -> None:
    client = make_client()
    client.set_token("tok_456")
    client.set_token("   ")
    client.set_token("")
    assert client._token == "tok_456"
    assert "token=tok_456&" in client._url(client._token)


def test_client_id_defaults_to_a_uuid_and_can_be_set() -> None:
    assert uuid.UUID(make_client().client_id).version == 4
    assert make_client(client_id="stable").client_id == "stable"
    assert "tok_123" not in repr(make_client())


async def test_subscriptions_are_kept_while_never_connected() -> None:
    client = make_client()
    channel = await client.subscribe("  agent:1  ")
    assert channel.name == "agent:1"
    assert await client.subscribe("agent:1") is channel
    await client.subscribe("channel:s", events=[" messages.* ", "messages.*", "", "tasks.*"])
    await client.subscribe_many(["run:9", {"topic": "channel:s", "events": ["tasks.*", "x.*"]}])
    assert client.get_subscribed_topics() == ["agent:1", "channel:s", "run:9"]
    assert client.get_subscriptions() == [
        {"topic": "agent:1", "events": ["*"]},
        {"topic": "channel:s", "events": ["messages.*", "tasks.*", "x.*"]},
        {"topic": "run:9", "events": ["*"]},
    ]

    await client.unsubscribe_many([{"topic": "channel:s", "events": ["messages.*", "nope"]}])
    await client.unsubscribe_many([{"topic": "unknown", "events": ["a"]}])
    await client.unsubscribe("agent:1")
    assert client.get_subscriptions() == [
        {"topic": "channel:s", "events": ["tasks.*", "x.*"]},
        {"topic": "run:9", "events": ["*"]},
    ]
    await client.unsubscribe_many([{"topic": "channel:s", "events": ["tasks.*", "x.*"]}, "run:9"])
    assert client.get_subscriptions() == []
    assert not client.is_connected()


async def test_blank_topics_are_rejected() -> None:
    client = make_client()
    with pytest.raises(FluxError):
        await client.subscribe("   ")
    with pytest.raises(FluxError):
        await client.subscribe_many([])
    with pytest.raises(FluxError):
        await client.subscribe_many(["", {"topic": "  "}])
    with pytest.raises(FluxError):
        await client.unsubscribe(" ")
    with pytest.raises(FluxError):
        await client.unsubscribe_many([])
    assert client.get_subscriptions() == []


async def test_send_message_before_connect_raises() -> None:
    client = make_client()
    with pytest.raises(FluxError, match="websocket is not connected"):
        await client.send_message("tables:leads", "ping", {"hello": "world"})
    channel = await client.subscribe("tables:leads")
    with pytest.raises(FluxError):
        await channel.send_message("ping", {})


async def test_wait_until_connected_requires_connect() -> None:
    with pytest.raises(FluxError, match="connect"):
        await make_client().wait_until_connected(timeout=0.01)


async def test_disconnect_without_connect_is_a_noop() -> None:
    client = make_client()
    await client.disconnect()
    assert not client.is_connected()


def test_bind_validation_and_unbind_forms() -> None:
    client = make_client()
    calls: list[tuple[Any, SocketMessage]] = []

    def handler(data: Any, message: SocketMessage) -> None:
        calls.append((data, message))

    def other(data: Any, message: SocketMessage) -> None:
        calls.append((data, message))

    with pytest.raises(FluxError, match="channel is required"):
        client.bind(" ", "status", handler)
    with pytest.raises(FluxError, match="event is required"):
        client.bind("runs:1", " ", handler)
    with pytest.raises(FluxError, match="channel is required"):
        client.unbind("")

    unbind = client.bind("runs:1", "status", handler)
    client.bind("runs:1", "status", other)
    client.bind("runs:1", "done", handler)
    client.unbind("runs:1", "status", handler)
    client.unbind("runs:1", "missing")
    client.unbind("unknown")
    assert _bound(client) == {"runs:1": {"status": [other], "done": [handler]}}

    client.unbind("runs:1", " done ")
    assert _bound(client) == {"runs:1": {"status": [other]}}
    unbind()  # already removed: harmless
    client.unbind("runs:1")
    assert _bound(client) == {}

    # A stale unbind function never touches handlers bound later.
    unbind = client.bind("runs:1", "status", handler)
    client.unbind("runs:1")
    client.bind("runs:1", "status", other)
    unbind()
    assert _bound(client) == {"runs:1": {"status": [other]}}


def test_handler_registration_returns_removers() -> None:
    client = make_client()
    remove = client.on_message(lambda message: None)
    client.on_error(lambda error: None)()
    client.on_state(lambda state: None)()
    remove()
    remove()


def _bound(client: FluxClient) -> dict[str, dict[str, list[object]]]:
    return {
        channel: {event: list(handlers) for event, handlers in events.items()}
        for channel, events in client._channel_handlers.items()
    }
