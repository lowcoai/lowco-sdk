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
    if status == 402:
        quota = parse_quota_exceeded(status, message, text)
        if quota is not None:
            return quota
    return LowcodbError(status_code=status, message=message, code=code, body=text)


#: Body code of a 402 from a base's gateway: the plan cap for the metered resource is reached.
CODE_QUOTA_EXCEEDED = "QUOTA_EXCEEDED"


class QuotaExceededError(LowcodbError):
    """Raised for a 402 ``QUOTA_EXCEEDED`` from the gateway.

    Carries the quota plane's body so a caller can explain, wait for ``period_end``
    or offer the upgrade. It is a :class:`LowcodbError`.
    """

    def __init__(
        self,
        *,
        status_code: int,
        message: str,
        body: str,
        meter: str,
        consumed: float,
        included: float,
        hard_cap: float | None,
        period_end: str | None = None,
        app_key: str | None = None,
        upgrade_app_key: str | None = None,
        upgrade_plans: list[str] | None = None,
    ) -> None:
        super().__init__(status_code=status_code, message=message, code=CODE_QUOTA_EXCEEDED, body=body)
        #: The metered resource, e.g. ``vlbrofrujc_employees_create``.
        self.meter = meter
        #: The period's usage and the plan's allowance.
        self.consumed = consumed
        self.included = included
        #: The ceiling that refused the call; ``None`` when the plan has none.
        self.hard_cap = hard_cap
        #: When the usage window resets (RFC 3339), when known.
        self.period_end = period_end
        #: Product whose plan applies, and what would lift the cap.
        self.app_key = app_key
        self.upgrade_app_key = upgrade_app_key
        self.upgrade_plans = upgrade_plans or []


def is_quota_exceeded(err: object) -> bool:
    """Whether ``err`` is a 402 ``QUOTA_EXCEEDED`` from the gateway."""
    return isinstance(err, QuotaExceededError)


def _num(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def parse_quota_exceeded(status: int, fallback_message: str, text: str) -> QuotaExceededError | None:
    """Reads a 402 body (the plane's ``QuotaError``) leniently: the keeper writes it at
    the top level, an envelope would nest it under ``error``."""
    try:
        raw = json.loads(text)
    except ValueError:
        return None
    if not isinstance(raw, dict):
        return None
    nested = raw.get("error")
    fields = nested if isinstance(nested, dict) and "code" in nested else raw
    if str(fields.get("code") or "").upper() != CODE_QUOTA_EXCEEDED:
        return None
    upgrade = fields.get("upgrade") if isinstance(fields.get("upgrade"), dict) else {}
    plans = upgrade.get("plans") if isinstance(upgrade.get("plans"), list) else None
    hard_cap = fields.get("hard_cap")
    message = fields.get("message") if isinstance(fields.get("message"), str) else ""
    return QuotaExceededError(
        status_code=status,
        message=message.strip() or fallback_message,
        body=text,
        meter=str(fields.get("meter") or ""),
        consumed=_num(fields.get("consumed")),
        included=_num(fields.get("included")),
        hard_cap=None if hard_cap is None else _num(hard_cap),
        period_end=fields.get("period_end") if isinstance(fields.get("period_end"), str) else None,
        app_key=fields.get("app_key") if isinstance(fields.get("app_key"), str) else None,
        upgrade_app_key=upgrade.get("app_key") or upgrade.get("appKey"),
        upgrade_plans=[str(p) for p in plans] if plans else None,
    )
