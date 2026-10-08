from __future__ import annotations

import json
from typing import Any


class AgentxError(Exception):
    """Raised for every HTTP-level non-2xx response from any agentx service.

    ``status_code`` is always set. ``message`` and ``code`` are populated when
    the service returns its standard JSON error envelope; otherwise
    ``message`` falls back to the raw response text and ``code`` is ``None``.
    ``body`` is the raw response text.

    JSON-RPC level errors from the executor are *not* raised: they come back in
    the ``error`` field of the :class:`~lowcoai.agentx.JSONRPCResponse`.
    """

    def __init__(
        self,
        *,
        status_code: int,
        message: str,
        code: str | int | None = None,
        body: str = "",
    ) -> None:
        self.status_code = status_code
        self.message = message or f"agentx: status={status_code}"
        self.code = code
        self.body = body
        super().__init__(self.message)

    def __repr__(self) -> str:
        return (
            f"AgentxError(status_code={self.status_code!r}, "
            f"message={self.message!r}, code={self.code!r})"
        )


def build_http_error(status: int, text: str) -> AgentxError:
    """Mirrors ``buildHttpError`` in the TS SDK: ``error.message`` / ``error.code``
    from the envelope, else a top-level ``message``, else the raw text."""
    message = text.strip()
    code: str | int | None = None
    try:
        parsed: Any = json.loads(text)
    except ValueError:
        parsed = None
    if isinstance(parsed, dict):
        envelope = parsed.get("error")
        envelope = envelope if isinstance(envelope, dict) else {}
        envelope_message = envelope.get("message")
        top_message = parsed.get("message")
        if isinstance(envelope_message, str) and envelope_message.strip():
            message = envelope_message
            raw_code = envelope.get("code")
            code = raw_code if isinstance(raw_code, (str, int)) else None
        elif isinstance(top_message, str) and top_message:
            message = top_message
    return AgentxError(status_code=status, message=message, code=code, body=text)
