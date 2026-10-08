from __future__ import annotations

import json
import re
from typing import Any

# The manager's error envelope puts the *opaque platform code* in
# ``error.message`` ("AAS-00105" and friends) and the **real** text in
# ``error.details``. Reading ``message`` alone would surface every DB-function
# failure as a bare "AAS-00105" with the cause discarded.
_OPAQUE_PLATFORM_CODE = re.compile(r"^AAS-\d+$")


class LowcodbError(Exception):
    """Raised for every non-2xx response from the lowcodb manager.

    ``status_code`` is always set. ``message`` and ``code`` are populated when
    the manager returns its standard JSON error envelope; otherwise
    ``message`` falls back to the raw response text and ``code`` is ``None``.
    The manager sends the numeric HTTP status in ``error.code``, so ``code``
    may be an ``int``.
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
        self.message = message or f"lowcodb: status={status_code}"
        self.code = code
        self.body = body
        super().__init__(self.message)

    def __repr__(self) -> str:
        return (
            f"LowcodbError(status_code={self.status_code!r}, "
            f"message={self.message!r}, code={self.code!r})"
        )


def build_http_error(status: int, text: str) -> LowcodbError:
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
            # Prefer the detail text whenever ``message`` is nothing but the
            # platform code. ``code`` is left alone (the manager sends the
            # numeric HTTP status there) and the platform code stays
            # recoverable from ``body``, so nothing is lost.
            details = envelope.get("details")
            details = details.strip() if isinstance(details, str) else ""
            if details and _OPAQUE_PLATFORM_CODE.match(envelope_message):
                message = details
        elif isinstance(parsed.get("message"), str) and parsed["message"]:
            message = parsed["message"]
    return LowcodbError(status_code=status, message=message, code=code, body=text)
