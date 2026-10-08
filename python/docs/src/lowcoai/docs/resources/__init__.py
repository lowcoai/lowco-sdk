"""Resource classes behind :class:`DocsClient` / :class:`AsyncDocsClient`.

One module per resource group; each holds a sync class and its asyncio twin.
They are normally reached through the client (``client.folders``,
``client.app_files``, ...) but can be built directly on top of an
:class:`HttpClient` / :class:`AsyncHttpClient`.
"""

from .app_files import AppFilesResource, AsyncAppFilesResource
from .automation import AsyncAutomationResource, AutomationResource
from .buckets import AsyncBucketsResource, BucketsResource
from .files import AsyncFilesResource, FilesResource
from .folders import AsyncFoldersResource, FoldersResource
from .library import AsyncLibraryResource, LibraryResource
from .nodes import AsyncNodesResource, NodesResource
from .sharing import AsyncSharingResource, SharingResource
from .triggers import AsyncTriggersResource, TriggersResource
from .webhooks import AsyncWebhooksResource, WebhooksResource

__all__ = [
    "AppFilesResource",
    "AsyncAppFilesResource",
    "AsyncAutomationResource",
    "AsyncBucketsResource",
    "AsyncFilesResource",
    "AsyncFoldersResource",
    "AsyncLibraryResource",
    "AsyncNodesResource",
    "AsyncSharingResource",
    "AsyncTriggersResource",
    "AsyncWebhooksResource",
    "AutomationResource",
    "BucketsResource",
    "FilesResource",
    "FoldersResource",
    "LibraryResource",
    "NodesResource",
    "SharingResource",
    "TriggersResource",
    "WebhooksResource",
]
