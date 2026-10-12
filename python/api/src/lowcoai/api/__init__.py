"""Official Python client for the Lowco API: PDF, render, OCR, Document AI,
QR and barcodes, with jobs, file inputs, webhooks and typed errors.

    from lowcoai.api import Files, LowcoApi

    lowco = LowcoApi()  # LOWCO_API_KEY
    answer = lowco.docai.invoice(file=Files.path("invoice.pdf"), mode="async")
    invoice = lowco.wait_for_result(answer)
"""

from __future__ import annotations

import uuid
from typing import Optional, TypeVar

from ._core import DEFAULT_BASE_URL, SDK_VERSION, Answer, Core, FileInput
from ._errors import LowcoApiError, LowcoJobError, LowcoTimeoutError
from ._files import FileRef, Files
from ._generated import API_VERSION, ERROR_REASONS, ErrorReason, GeneratedClient
from ._webhooks import SIGNATURE_HEADER, LowcoSignatureError, construct_event, verify_signature

__all__ = [
    "API_VERSION", "DEFAULT_BASE_URL", "ERROR_REASONS", "SDK_VERSION", "SIGNATURE_HEADER",
    "Answer", "ErrorReason", "FileInput", "FileRef", "Files", "LowcoApi", "LowcoApiError", "LowcoJobError",
    "LowcoSignatureError", "LowcoTimeoutError", "construct_event", "new_idempotency_key", "verify_signature",
]
__version__ = SDK_VERSION

T = TypeVar("T")


def new_idempotency_key() -> str:
    """A new Idempotency-Key: store it with your record before calling, and reuse it on retries."""
    return str(uuid.uuid4())


class LowcoApi(GeneratedClient):
    """The Lowco API client. ``api_key`` defaults to LOWCO_API_KEY and
    ``base_url`` to LOWCO_API_BASE_URL, else https://api.lowco.ai."""

    def __init__(self, api_key: Optional[str] = None, *, base_url: Optional[str] = None, timeout: float = 60.0,
                 max_retries: int = 2) -> None:
        super().__init__(Core(api_key, base_url=base_url, timeout=timeout, max_retries=max_retries))

    def wait_for_result(self, answer: Answer[T], *, timeout: float = 300.0, max_interval: float = 10.0) -> T:
        """The result of an operation's answer: inline data, or the job's result once it finishes."""
        return self._core.wait_for_result(answer, timeout=timeout, max_interval=max_interval)
