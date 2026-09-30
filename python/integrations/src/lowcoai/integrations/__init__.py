"""Official Python client for the integrations-manager product."""

from . import types as _types
from ._base import BASE_URL
from ._client import AsyncIntegrationsClient, IntegrationsClient
from ._errors import IntegrationsError
from ._http import AsyncHttpClient, HttpClient
from .types import *  # noqa: F403

__version__ = "0.1.0"

__all__ = [
    "BASE_URL",
    "AsyncHttpClient",
    "AsyncIntegrationsClient",
    "HttpClient",
    "IntegrationsClient",
    "IntegrationsError",
    "__version__",
]
__all__ += _types.__all__
