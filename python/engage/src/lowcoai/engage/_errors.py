from __future__ import annotations

import json
import re
from typing import Any

# The platform error envelope puts an opaque code ("AAS-00105") in
# ``error.message`` and the real text in ``error.details``.
_OPAQUE_PLATFORM_CODE = re.compile(r"^AAS-\d+$")


class EngageError(Exception):
    """Raised when the engage service answers with a non-2xx status.

    ``status_code`` is always set. ``message`` comes from the service's JSON
    error envelope when there is one, otherwise it is the raw response text.
    ``code`` is the envelope's ``error.code`` (the service sends the numeric
    HTTP status there) or ``None``. ``body`` is the raw response text.
    """

    def __init__(
        self,
        status_code: int,
        message: str,
        body: str = "",
        *,
        code: str | int | None = None,
    ) -> None:
        self.status_code = status_code
        self.message = message or f"engage: status={status_code}"
        self.body = body
        self.code = code
        super().__init__(self.message)

    def __repr__(self) -> str:
        return (
            f"EngageError(status_code={self.status_code!r}, "
            f"message={self.message!r}, code={self.code!r})"
        )


def build_http_error(status: int, text: str) -> EngageError:
    message = text.strip()
    code: str | int | None = None
    try:
        parsed: Any = json.loads(text)
    except ValueError:
        parsed = None
    if isinstance(parsed, dict):
        envelope = parsed.get("error")
        envelope_message = ""
        if isinstance(envelope, dict) and isinstance(envelope.get("message"), str):
            envelope_message = envelope["message"].strip()
        if isinstance(envelope, dict) and envelope_message:
            message = envelope_message
            code = envelope.get("code")
            details = envelope.get("details")
            details = details.strip() if isinstance(details, str) else ""
            if details and _OPAQUE_PLATFORM_CODE.match(envelope_message):
                message = details
        elif isinstance(parsed.get("message"), str) and parsed["message"]:
            message = parsed["message"]
        elif isinstance(envelope, str) and envelope:
            message = envelope
    return EngageError(status, message, text, code=code)
