from __future__ import annotations

from typing import Any, Dict, List, Optional

__all__ = ["LowcoApiError", "LowcoJobError", "LowcoTimeoutError"]


class LowcoApiError(Exception):
    """Raised for every failed call: an error envelope, a network failure, a
    timeout or invalid input.

    * ``status`` — the HTTP status, or ``0`` when no response was received.
    * ``reason`` — the stable error code (``error.reason``): branch on this,
      not on ``message``. ``lowcoai.api.ERROR_REASONS`` describes each one.
    * ``param`` — the parameter at fault; ``details`` — each failing item.
    * ``request_id`` — quote it to support; ``doc_url`` — the reason's entry
      on docs.lowco.ai/api/errors.
    * ``retryable`` — whether the same request may succeed later;
      ``retry_after`` — seconds to wait (Retry-After) when the API said.
    """

    def __init__(self, message: str, *, status: int, reason: str, param: Optional[str] = None,
                 details: Optional[List[Dict[str, Any]]] = None, request_id: Optional[str] = None,
                 doc_url: Optional[str] = None, retryable: Optional[bool] = None,
                 retry_after: Optional[int] = None, payload: Any = None) -> None:
        super().__init__(message)
        self.message = message
        self.status = status
        self.reason = reason
        self.param = param
        self.details = details
        self.request_id = request_id
        self.doc_url = doc_url
        self.retryable = retryable
        self.retry_after = retry_after
        self.payload = payload

    def __repr__(self) -> str:
        return f"{type(self).__name__}(status={self.status!r}, reason={self.reason!r}, message={self.message!r}, request_id={self.request_id!r})"


class LowcoJobError(LowcoApiError):
    """Raised by ``jobs.wait`` when a job failed or was cancelled; ``job`` is its last state."""

    def __init__(self, message: str, *, job: Dict[str, Any], **kwargs: Any) -> None:
        super().__init__(message, payload=job, **kwargs)
        self.job = job


class LowcoTimeoutError(Exception):
    """Raised by ``jobs.wait`` when the job is still running at the timeout."""

    def __init__(self, job_id: str, timeout: float) -> None:
        super().__init__(f"Job {job_id} did not finish within {timeout} s")
        self.job_id = job_id
