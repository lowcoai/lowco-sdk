from __future__ import annotations

import json
from typing import Any


class LowcoAuthError(Exception):
    """Raised when the OAuth flow fails.

    - Token endpoint answered non-2xx: ``message`` is
      ``"Authorization code exchange failed."`` or
      ``"Refresh token exchange failed."`` (the React SDK's messages),
      ``status_code`` and the raw ``body`` are set, and ``code`` is the
      response's ``error`` field when it has one (e.g. ``"invalid_grant"``).
    - Redirect callback carried an OAuth error: ``code`` is the ``error``
      parameter (e.g. ``"access_denied"``).
    - Callback without ``code`` / ``state``, state mismatch, or no usable
      session (``"Not authenticated."`` / ``"Session expired."``):
      only ``message`` is set.
    """

    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = None,
        body: str | None = None,
        code: str | None = None,
    ) -> None:
        self.message = message
        self.status_code = status_code
        self.body = body
        self.code = code
        super().__init__(message)

    def __repr__(self) -> str:
        return (
            f"LowcoAuthError(message={self.message!r}, "
            f"status_code={self.status_code!r}, code={self.code!r})"
        )


def error_code_from_body(text: str) -> str | None:
    """Reads ``error`` (string) or ``error.code`` from a JSON error body."""
    try:
        parsed: Any = json.loads(text)
    except ValueError:
        return None
    if not isinstance(parsed, dict):
        return None
    error = parsed.get("error")
    if isinstance(error, str) and error:
        return error
    if isinstance(error, dict) and error.get("code") is not None:
        return str(error["code"])
    return None
