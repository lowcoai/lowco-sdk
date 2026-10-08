"""Official Python client for the agentx backend (agent-manager, agent-kb, agent-executor)."""

from . import types as _types
from ._base import BASE_URL
from ._client import AgentxClient, AsyncAgentxClient
from ._errors import AgentxError
from ._executor import AsyncExecutorClient, ExecutorClient, StreamEvent, try_parse_message
from ._kb import AsyncKBClient, KBClient
from ._manager import AsyncManagerClient, ManagerClient
from .types import *  # noqa: F403

__version__ = "0.1.0"

__all__ = [
    "BASE_URL",
    "AgentxClient",
    "AgentxError",
    "AsyncAgentxClient",
    "AsyncExecutorClient",
    "AsyncKBClient",
    "AsyncManagerClient",
    "ExecutorClient",
    "KBClient",
    "ManagerClient",
    "StreamEvent",
    "__version__",
    "try_parse_message",
]
__all__ += _types.__all__
