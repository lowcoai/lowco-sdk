from __future__ import annotations

from typing import Any

__all__ = ["WorkflowError"]


class WorkflowError(Exception):
    """Raised for every non-2xx response and every transport failure.

    Mirrors the TypeScript ``WorkflowError``:

    * ``message`` — ``"Request failed with status <n>"`` for HTTP errors, or the
      underlying error text for transport failures / timeouts.
    * ``status`` — the HTTP status code, or ``0`` when no response was received
      (connection error, timeout).
    * ``payload`` — the parsed JSON error body; the raw text when the body is
      not JSON; ``None`` when it is empty or no response was received.
    """

    def __init__(self, message: str, status: int, payload: Any = None) -> None:
        super().__init__(message)
        self.message = message
        self.status = status
        self.payload = payload

    def __repr__(self) -> str:
        return (
            f"WorkflowError(message={self.message!r}, status={self.status!r}, "
            f"payload={self.payload!r})"
        )
