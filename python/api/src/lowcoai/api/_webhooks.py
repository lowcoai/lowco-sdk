from __future__ import annotations

import hashlib
import hmac
import json
import time
from typing import Any, Dict, Optional, Union

__all__ = ["SIGNATURE_HEADER", "LowcoSignatureError", "construct_event", "verify_signature"]

SIGNATURE_HEADER = "Lowco-Signature"


class LowcoSignatureError(Exception):
    """Raised by construct_event when a delivery's signature does not verify."""


def verify_signature(header: Optional[str], raw_body: Union[str, bytes], secret: str, *,
                     tolerance: int = 300, now: Optional[float] = None) -> bool:
    """Verifies ``Lowco-Signature: t=<unix seconds>,v1=<hex HMAC-SHA256(secret, "<t>.<raw body>")>``.

    Pass the raw request body (before JSON parsing) and the endpoint's
    ``whsec_…`` secret as-is. During a secret rotation the header may carry
    several v1 values; any one matching verifies.
    """
    if not header:
        return False
    t, sigs = 0, []
    for piece in header.split(","):
        k, _, v = piece.strip().partition("=")
        if k == "t":
            try:
                t = int(v)
            except ValueError:
                return False
        elif k == "v1" and v:
            sigs.append(v)
    if not t or not sigs:
        return False
    if abs((time.time() if now is None else now) - t) > tolerance:
        return False
    body = raw_body.encode("utf-8") if isinstance(raw_body, str) else raw_body
    expected = hmac.new(secret.encode(), f"{t}.".encode() + body, hashlib.sha256).hexdigest()
    return any(hmac.compare_digest(s, expected) for s in sigs)


def construct_event(raw_body: Union[str, bytes], header: Optional[str], secret: str, *,
                    tolerance: int = 300, now: Optional[float] = None) -> Dict[str, Any]:
    """Verifies a delivery and returns its event (id, type, created_at, environment, data)."""
    if not verify_signature(header, raw_body, secret, tolerance=tolerance, now=now):
        raise LowcoSignatureError("The Lowco-Signature does not match this body and secret, or its timestamp is too old")
    text = raw_body.decode("utf-8") if isinstance(raw_body, bytes) else raw_body
    event: Dict[str, Any] = json.loads(text)
    return event
