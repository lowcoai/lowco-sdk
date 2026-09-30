from __future__ import annotations

import json
from collections.abc import AsyncGenerator, Generator
from dataclasses import dataclass
from typing import cast

from ._base import ACCEPT_EVENT_STREAM, decode_rpc_response, join_path, rpc_request
from ._sse import SSEParser
from ._transport import AsyncTransport, SyncTransport
from .types import A2AMessage, JSONRPCResponse, MessageSendParams

__all__ = ["AsyncExecutorClient", "ExecutorClient", "StreamEvent", "try_parse_message"]


@dataclass(frozen=True)
class StreamEvent:
    """A single SSE event delivered by ``stream_message``.

    ``data`` is the raw payload of the event (its ``data:`` lines joined with
    ``"\\n"``), which is typically a JSON :class:`~lowcoai.agentx.A2AMessage` but may
    also be a tool / status frame. Use :func:`try_parse_message` for a
    message-typed view.
    """

    data: str


def try_parse_message(ev: StreamEvent) -> A2AMessage | None:
    """Decodes ``ev.data`` as JSON; returns ``None`` unless it is a JSON object.

    Like the TS SDK, the object is not validated beyond that: tool / status
    frames come back too, so check ``kind`` when it matters.
    """
    try:
        parsed = json.loads(ev.data)
    except ValueError:
        return None
    if not isinstance(parsed, dict):
        return None
    return cast(A2AMessage, parsed)


class ExecutorClient:
    """Agent-executor service routes (A2A JSON-RPC over HTTP + SSE).

    Obtain it as ``AgentxClient(...).executor``.
    """

    def __init__(self, transport: SyncTransport, api_base_path: str) -> None:
        self._t = transport
        self._api_base_path = api_base_path

    def _path(self, *parts: str) -> str:
        return join_path(self._api_base_path, *parts)

    def health(self) -> None:
        """``GET /health`` at the host root."""
        self._t.request_void("GET", "/health")

    def send_message(self, agent_id: str, params: MessageSendParams) -> JSONRPCResponse:
        """Performs a synchronous ``message/send`` call.

        The JSON-RPC ``id`` doubles as the target agent identifier (service
        convention). The raw JSON-RPC response is returned: JSON-RPC level
        errors are in its ``error`` field, not raised. An empty / 204 body
        yields ``{"jsonrpc": "2.0", "id": agent_id}``.
        """
        resp = self._t.send("POST", self._path("execute"), body=rpc_request(agent_id, params))
        return decode_rpc_response(resp.status_code, resp.text, agent_id)

    def stream_message(
        self, agent_id: str, params: MessageSendParams
    ) -> Generator[StreamEvent, None, None]:
        """Streams a ``message/send`` call, yielding one :class:`StreamEvent` per SSE event.

        The request is sent lazily, when iteration starts; a non-2xx response
        raises :class:`~lowcoai.agentx.AgentxError` at that point. The read
        timeout does not apply to the stream (connect / write / pool timeouts
        still do). Breaking out of the loop (or calling ``.close()`` on the
        returned generator, e.g. via ``contextlib.closing``) closes the
        connection::

            for ev in client.executor.stream_message(agent_id, params):
                msg = try_parse_message(ev)
                print("delta:" if msg else "raw:", msg or ev.data)
        """
        body = rpc_request(agent_id, params)
        with self._t.stream(
            "POST", self._path("execute"), body=body, accept=ACCEPT_EVENT_STREAM
        ) as resp:
            parser = SSEParser()
            for chunk in resp.iter_bytes():
                for data in parser.feed(chunk):
                    yield StreamEvent(data)
            for data in parser.finish():
                yield StreamEvent(data)


class AsyncExecutorClient:
    """Agent-executor service routes (A2A JSON-RPC over HTTP + SSE).

    Obtain it as ``AsyncAgentxClient(...).executor``.
    """

    def __init__(self, transport: AsyncTransport, api_base_path: str) -> None:
        self._t = transport
        self._api_base_path = api_base_path

    def _path(self, *parts: str) -> str:
        return join_path(self._api_base_path, *parts)

    async def health(self) -> None:
        """``GET /health`` at the host root."""
        await self._t.request_void("GET", "/health")

    async def send_message(self, agent_id: str, params: MessageSendParams) -> JSONRPCResponse:
        """Performs a synchronous ``message/send`` call.

        The JSON-RPC ``id`` doubles as the target agent identifier (service
        convention). The raw JSON-RPC response is returned: JSON-RPC level
        errors are in its ``error`` field, not raised. An empty / 204 body
        yields ``{"jsonrpc": "2.0", "id": agent_id}``.
        """
        resp = await self._t.send("POST", self._path("execute"), body=rpc_request(agent_id, params))
        return decode_rpc_response(resp.status_code, resp.text, agent_id)

    async def stream_message(
        self, agent_id: str, params: MessageSendParams
    ) -> AsyncGenerator[StreamEvent, None]:
        """Streams a ``message/send`` call, yielding one :class:`StreamEvent` per SSE event.

        The request is sent lazily, when iteration starts; a non-2xx response
        raises :class:`~lowcoai.agentx.AgentxError` at that point. The read
        timeout does not apply to the stream (connect / write / pool timeouts
        still do). Use ``contextlib.aclosing`` (or call ``await stream.aclose()``)
        to close the connection deterministically when stopping early::

            async with aclosing(client.executor.stream_message(agent_id, params)) as events:
                async for ev in events:
                    msg = try_parse_message(ev)
                    print("delta:" if msg else "raw:", msg or ev.data)
        """
        body = rpc_request(agent_id, params)
        async with self._t.stream(
            "POST", self._path("execute"), body=body, accept=ACCEPT_EVENT_STREAM
        ) as resp:
            parser = SSEParser()
            async for chunk in resp.aiter_bytes():
                for data in parser.feed(chunk):
                    yield StreamEvent(data)
            for data in parser.finish():
                yield StreamEvent(data)
