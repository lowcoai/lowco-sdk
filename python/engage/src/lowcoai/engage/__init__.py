"""Official server-side Python client for the lowco engage event-tracking service."""

from . import types as _types
from ._base import (
    ALIAS_ANONYMOUS,
    ALIAS_EMAIL,
    ALIAS_EXTERNAL,
    ALIAS_PATH,
    ALIAS_PHONE,
    ATTRIBUTION_KEYS,
    BASE_URL,
    CONSENT_CHANNELS,
    CONSENT_OPTED_IN,
    CONSENT_OPTED_OUT,
    CONSENT_PENDING,
    HEADER_API_KEY,
    HEADER_ENGAGE_APP_ID,
    HEADER_ORG_ID,
    IDENTIFY_EVENT,
    MAX_BATCH,
    MERGE_PATH,
    PAGE_VIEW_EVENT,
    TRACK_BATCH_PATH,
    TRACK_PATH,
    attribution_from_url,
    is_api_key,
)
from ._client import AsyncEngageClient, EngageClient
from ._errors import EngageError
from .types import *  # noqa: F403

__version__ = "0.2.0"

__all__ = [
    "ALIAS_ANONYMOUS",
    "ALIAS_EMAIL",
    "ALIAS_EXTERNAL",
    "ALIAS_PATH",
    "ALIAS_PHONE",
    "ATTRIBUTION_KEYS",
    "BASE_URL",
    "CONSENT_CHANNELS",
    "CONSENT_OPTED_IN",
    "CONSENT_OPTED_OUT",
    "CONSENT_PENDING",
    "HEADER_API_KEY",
    "HEADER_ENGAGE_APP_ID",
    "HEADER_ORG_ID",
    "IDENTIFY_EVENT",
    "MAX_BATCH",
    "MERGE_PATH",
    "PAGE_VIEW_EVENT",
    "TRACK_BATCH_PATH",
    "TRACK_PATH",
    "AsyncEngageClient",
    "EngageClient",
    "EngageError",
    "__version__",
    "attribution_from_url",
    "is_api_key",
]
__all__ += _types.__all__
