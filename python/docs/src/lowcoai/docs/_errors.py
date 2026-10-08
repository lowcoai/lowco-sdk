from __future__ import annotations

from typing import Any

__all__ = ["DocsError"]


class DocsError(Exception):
    """Raised for every non-2xx response, every transport failure, every
    response the SDK cannot decode and every path segment it refuses to send.

    * ``message`` — the best message the error body offers: for a
      ``{"status": 0, "error": {...}}`` body, ``error.details`` when
      ``error.message`` is a platform code (e.g. ``AAS-00106``), else
      ``error.message`` (then ``details``); for a ``{"message": "..."}`` body,
      ``message``; ``"Request failed with status <n>"`` when there is none. For
      transport failures / timeouts, the underlying error text.
    * ``status`` — the HTTP status code, or ``0`` when no response was received
      (connection error, timeout, rejected ``.`` / ``..`` path segment).
    * ``code`` — the platform error code (``error.message`` of an enveloped error
      when it looks like ``AAS-00106``), else ``None``.
    * ``payload`` — the parsed JSON error body; the raw text when the body is
      not JSON; ``None`` when it is empty or no response was received.
    """

    def __init__(
        self, message: str, status: int, payload: Any = None, *, code: str | None = None
    ) -> None:
        super().__init__(message)
        self.message = message
        self.status = status
        self.payload = payload
        self.code = code

    def __repr__(self) -> str:
        return (
            f"DocsError(message={self.message!r}, status={self.status!r}, "
            f"code={self.code!r}, payload={self.payload!r})"
        )
