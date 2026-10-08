"""Framework-agnostic helpers for the lowco OAuth 2.0 Authorization Code + PKCE flow."""

from . import types as _types
from ._base import DEFAULT_SCOPE
from ._client import AsyncLowcoAuthClient, LowcoAuthClient
from ._errors import LowcoAuthError
from ._tokens import (
    TOKEN_REFRESH_SKEW_SECONDS,
    can_recover_session,
    get_user,
    is_access_token_valid,
)
from .types import *  # noqa: F403

__version__ = "0.1.0"

__all__ = [
    "DEFAULT_SCOPE",
    "TOKEN_REFRESH_SKEW_SECONDS",
    "AsyncLowcoAuthClient",
    "LowcoAuthClient",
    "LowcoAuthError",
    "__version__",
    "can_recover_session",
    "get_user",
    "is_access_token_valid",
]
__all__ += _types.__all__
