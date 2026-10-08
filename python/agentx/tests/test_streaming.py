"""executor.stream_message over a mocked SSE response (sync + async)."""

from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncIterator, Iterator
from contextlib import aclosing, closing
from typing import Any

import httpx
import pytest

from lowcoai.agentx import (
    AgentxClient,
    AgentxError,
    AsyncAgentxClient,
    MessageSendParams,
    StreamEvent,
    try_parse_message,
)

PARAMS: MessageSendParams = {
    "message": {
        "role": "user",
        "messageId": "msg_001",
        "kind": "message",
        "parts": [{"kind": "text", "text": "Hello!"}],
    },
}

MSG_1 = {
    "kind": "message",
    "role": "assistant",
    "messageId": "r1",
    "parts": [{"kind": "text", "text": "Hi"}],
}

# Chunk boundaries fall inside "data:", inside a JSON payload, between "\r\n"
# and "\r\n", and inside a multi-byte character; the last event has no
# terminating blank line.
CHUNKS = [
    b": connected\n\nevent: message\nda",
    b"ta: " + json.dumps(MSG_1).encode()[:20],
    json.dumps(MSG_1).encode()[20:] + b"\n\n",
    b"id: 7\r\ndata: first line\r\ndata: second line\r\n",
    b"\r\nretry: 500\n\ndata: caf\xc3",
    b"\xa9\n\nevent: done\ndata: [DONE]",
]
EXPECTED = [
    StreamEvent(json.dumps(MSG_1)),
    StreamEvent("first line\nsecond line"),
    StreamEvent("café"),
    StreamEvent("[DONE]"),
]


class ChunkStream(httpx.SyncByteStream, httpx.AsyncByteStream):
    """A response body delivered chunk by chunk that records whether it was closed."""

    def __init__(self, chunks: list[bytes]) -> None:
        self.chunks = chunks
        self.served = 0
        self.closed = False

    def __iter__(self) -> Iterator[bytes]:
        for chunk in self.chunks:
            self.served += 1
            yield chunk

    async def __aiter__(self) -> AsyncIterator[bytes]:
        for chunk in self.chunks:
            self.served += 1
            yield chunk

    def close(self) -> None:
        self.closed = True

    async def aclose(self) -> None:
        self.closed = True


class Server:
    def __init__(self, chunks: list[bytes] | None = None, status: int = 200) -> None:
        self.stream = ChunkStream(chunks if chunks is not None else CHUNKS)
        self.status = status
        self.requests: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        return httpx.Response(
            self.status, headers={"Content-Type": "text/event-stream"}, stream=self.stream
        )


def sync_client(server: Server, **kwargs: Any) -> AgentxClient:
    return AgentxClient(
        "tok_123",
        org_id="org_1",
        http_client=httpx.Client(transport=httpx.MockTransport(server)),
        **kwargs,
    )


def async_client(server: Server, **kwargs: Any) -> AsyncAgentxClient:
    return AsyncAgentxClient(
        "tok_123",
        org_id="org_1",
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(server)),
        **kwargs,
    )


def check_request(server: Server) -> None:
    assert len(server.requests) == 1
    req = server.requests[0]
    assert req.method == "POST"
    assert str(req.url) == "https://api.lowco.ai/v1/agentx/executors/execute"
    assert req.headers["Accept"] == "text/event-stream"
    assert req.headers["Content-Type"] == "application/json"
    assert req.headers["Authorization"] == "Bearer tok_123"
    assert req.headers["X-Org-Id"] == "org_1"
    assert json.loads(req.content) == {
        "jsonrpc": "2.0",
        "method": "message/send",
        "params": PARAMS,
        "id": "agent_1",
    }
    # The read timeout is disabled for the stream; the others are kept.
    assert req.extensions["timeout"] == {
        "connect": 30.0,
        "read": None,
        "write": 30.0,
        "pool": 30.0,
    }


# --- sync ----------------------------------------------------------------------


def test_sync_stream_yields_events() -> None:
    server = Server()
    client = sync_client(server)
    events = list(client.executor.stream_message("agent_1", PARAMS))
    assert events == EXPECTED
    check_request(server)
    assert server.stream.closed


def test_sync_stream_request_is_lazy() -> None:
    server = Server()
    stream = sync_client(server).executor.stream_message("agent_1", PARAMS)
    assert server.requests == []
    assert next(stream) == EXPECTED[0]
    assert len(server.requests) == 1
    stream.close()
    assert server.stream.closed


def test_sync_break_closes_the_response() -> None:
    server = Server()
    client = sync_client(server)
    for ev in client.executor.stream_message("agent_1", PARAMS):
        assert ev == EXPECTED[0]
        break
    assert server.stream.closed
    assert server.stream.served < len(CHUNKS)


def test_sync_closing_context_manager_closes_the_response() -> None:
    server = Server()
    client = sync_client(server)
    with closing(client.executor.stream_message("agent_1", PARAMS)) as events:
        assert next(events) == EXPECTED[0]
    assert server.stream.closed


def test_sync_stream_http_error_raises_and_closes() -> None:
    body = json.dumps({"error": {"code": "UNAUTHORIZED", "message": "bad token"}}).encode()
    server = Server([body], status=401)
    client = sync_client(server)
    with pytest.raises(AgentxError) as info:
        list(client.executor.stream_message("agent_1", PARAMS))
    assert info.value.status_code == 401
    assert info.value.message == "bad token"
    assert info.value.code == "UNAUTHORIZED"
    assert info.value.body == body.decode()
    assert server.stream.closed


def test_sync_stream_timeout_none_disables_all_timeouts() -> None:
    server = Server([b"data: x\n\n"])
    client = sync_client(server, timeout=None)
    assert list(client.executor.stream_message("agent_1", PARAMS)) == [StreamEvent("x")]
    assert set(server.requests[0].extensions["timeout"].values()) == {None}


def test_empty_stream_yields_nothing() -> None:
    server = Server([])
    assert list(sync_client(server).executor.stream_message("agent_1", PARAMS)) == []


def test_try_parse_message() -> None:
    assert try_parse_message(EXPECTED[0]) == MSG_1
    assert try_parse_message(StreamEvent("[DONE]")) is None
    assert try_parse_message(StreamEvent("not json")) is None
    assert try_parse_message(StreamEvent("42")) is None
    # Not validated beyond "is a JSON object", like the TS SDK: status frames come back too.
    frame: Any = try_parse_message(StreamEvent('{"kind": "status-update"}'))
    assert frame == {"kind": "status-update"}


def test_stream_event_is_frozen() -> None:
    ev = StreamEvent("x")
    with pytest.raises(AttributeError):
        ev.data = "y"  # type: ignore[misc]


# --- async ---------------------------------------------------------------------


async def test_async_stream_yields_events() -> None:
    server = Server()
    client = async_client(server)
    events = [ev async for ev in client.executor.stream_message("agent_1", PARAMS)]
    assert events == EXPECTED
    check_request(server)
    assert server.stream.closed


async def test_async_aclosing_closes_the_response_on_early_exit() -> None:
    server = Server()
    client = async_client(server)
    async with aclosing(client.executor.stream_message("agent_1", PARAMS)) as events:
        async for ev in events:
            assert ev == EXPECTED[0]
            break
    assert server.stream.closed
    assert server.stream.served < len(CHUNKS)


async def test_async_break_closes_the_response() -> None:
    server = Server()
    client = async_client(server)
    async for ev in client.executor.stream_message("agent_1", PARAMS):
        assert ev == EXPECTED[0]
        break
    # Without aclosing() the abandoned generator is finalized by the event loop.
    for _ in range(20):
        if server.stream.closed:
            break
        await asyncio.sleep(0)
    assert server.stream.closed


async def test_async_stream_http_error_raises_and_closes() -> None:
    server = Server([b'{"message": "rate limited"}'], status=429)
    client = async_client(server)
    with pytest.raises(AgentxError) as info:
        async for _ in client.executor.stream_message("agent_1", PARAMS):
            pass
    assert info.value.status_code == 429
    assert info.value.message == "rate limited"
    assert info.value.code is None
    assert server.stream.closed


async def test_async_stream_request_is_lazy() -> None:
    server = Server()
    stream = async_client(server).executor.stream_message("agent_1", PARAMS)
    assert server.requests == []
    assert await stream.__anext__() == EXPECTED[0]
    await stream.aclose()
    assert len(server.requests) == 1
    assert server.stream.closed
