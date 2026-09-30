from __future__ import annotations

from collections.abc import Mapping
from datetime import datetime
from typing import Any

import httpx
from typing_extensions import Self

from ._base import (
    DEFAULT_TIMEOUT,
    IDENTIFY_EVENT,
    PAGE_VIEW_EVENT,
    BaseClient,
    check_status,
    encode_event,
)
from .types import DeviceInfo, Event, LocationInfo

__all__ = ["AsyncEngageClient", "EngageClient"]


class EngageClient(BaseClient):
    """Server-side client for the lowco engage track API.

    Every call sends one event to ``POST https://api.lowco.ai/v1/engage/track``
    with ``Authorization: Bearer <api_key>`` and ``X-Org-Id: <org_id>``.

    Unlike the browser SDK, the client is **stateless**: it never remembers a
    user id (``identify_user`` does not bind later events to that user), keeps
    no session, and captures no page / device / location information on its
    own. One instance is meant to be shared by every request a server handles,
    so pass ``user_id``, ``session_id``, ``device_info`` and ``location`` on
    each call. Events without a ``device_id`` use :attr:`device_id` (a uuid4
    generated per client unless one is configured).

    Use it as a context manager, or call :meth:`close`, to release the
    underlying connection pool.
    """

    def __init__(
        self,
        api_key: str,
        org_id: str,
        *,
        device_id: str | None = None,
        timeout: float | None = DEFAULT_TIMEOUT,
        http_client: httpx.Client | None = None,
    ) -> None:
        """
        Args:
            api_key: Engage API key, sent as ``Authorization: Bearer <api_key>``. Required.
            org_id: Organisation id, sent as the ``X-Org-Id`` header. Required.
            device_id: Default ``device_id`` for events that don't pass one.
                Defaults to a uuid4 generated for this client instance.
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
            http_client: Custom ``httpx.Client`` (proxies, retries, mocks). It is
                not closed by :meth:`close`.
        """
        super().__init__(api_key, org_id, device_id=device_id)
        self._timeout = timeout
        self._owns_http = http_client is None
        self._http = http_client if http_client is not None else httpx.Client()

    def close(self) -> None:
        if self._owns_http:
            self._http.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()

    def track(
        self,
        event_name: str,
        properties: Mapping[str, Any] | None = None,
        *,
        user_id: str | None = None,
        device_id: str | None = None,
        session_id: str | None = None,
        device_info: DeviceInfo | None = None,
        location: LocationInfo | None = None,
        event_time: datetime | None = None,
    ) -> None:
        """Sends a custom event.

        ``properties`` become ``event_data``. ``event_time`` defaults to now; a
        naive datetime is treated as UTC. Raises :class:`EngageError` on a
        non-2xx response.
        """
        self._send(
            self._build_event(
                event_name,
                properties,
                user_id=user_id,
                device_id=device_id,
                session_id=session_id,
                device_info=device_info,
                location=location,
                event_time=event_time,
            )
        )

    def page(
        self,
        properties: Mapping[str, Any] | None = None,
        *,
        user_id: str | None = None,
        device_id: str | None = None,
        session_id: str | None = None,
        device_info: DeviceInfo | None = None,
        location: LocationInfo | None = None,
        event_time: datetime | None = None,
    ) -> None:
        """Sends a ``page_view`` event (``properties`` such as path, url, title, referrer)."""
        self._send(
            self._build_event(
                PAGE_VIEW_EVENT,
                properties,
                user_id=user_id,
                device_id=device_id,
                session_id=session_id,
                device_info=device_info,
                location=location,
                event_time=event_time,
            )
        )

    def identify_user(
        self,
        user_id: str,
        properties: Mapping[str, Any] | None = None,
        *,
        device_id: str | None = None,
        session_id: str | None = None,
        device_info: DeviceInfo | None = None,
        location: LocationInfo | None = None,
        event_time: datetime | None = None,
    ) -> None:
        """Sends an ``_lowco_identify`` event linking ``user_id`` to ``device_id``.

        The user id is **not** remembered for later calls (see the class docs).
        """
        if not user_id or not user_id.strip():
            raise ValueError("user_id is required")
        self._send(
            self._build_event(
                IDENTIFY_EVENT,
                properties,
                user_id=user_id,
                device_id=device_id,
                session_id=session_id,
                device_info=device_info,
                location=location,
                event_time=event_time,
            )
        )

    def _send(self, event: Event) -> None:
        resp = self._http.post(
            self._track_url,
            content=encode_event(event),
            headers=self._headers,
            timeout=self._timeout,
        )
        check_status(resp.status_code, resp.text)


class AsyncEngageClient(BaseClient):
    """Asyncio client for the lowco engage track API (same surface as :class:`EngageClient`).

    Stateless like :class:`EngageClient`: nothing about a user is remembered
    between calls. Use it as an async context manager, or call :meth:`aclose`,
    to release the underlying connection pool.
    """

    def __init__(
        self,
        api_key: str,
        org_id: str,
        *,
        device_id: str | None = None,
        timeout: float | None = DEFAULT_TIMEOUT,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        """
        Args:
            api_key: Engage API key, sent as ``Authorization: Bearer <api_key>``. Required.
            org_id: Organisation id, sent as the ``X-Org-Id`` header. Required.
            device_id: Default ``device_id`` for events that don't pass one.
                Defaults to a uuid4 generated for this client instance.
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
            http_client: Custom ``httpx.AsyncClient`` (proxies, retries, mocks). It is
                not closed by :meth:`aclose`.
        """
        super().__init__(api_key, org_id, device_id=device_id)
        self._timeout = timeout
        self._owns_http = http_client is None
        self._http = http_client if http_client is not None else httpx.AsyncClient()

    async def aclose(self) -> None:
        if self._owns_http:
            await self._http.aclose()

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(self, *exc_info: object) -> None:
        await self.aclose()

    async def track(
        self,
        event_name: str,
        properties: Mapping[str, Any] | None = None,
        *,
        user_id: str | None = None,
        device_id: str | None = None,
        session_id: str | None = None,
        device_info: DeviceInfo | None = None,
        location: LocationInfo | None = None,
        event_time: datetime | None = None,
    ) -> None:
        """Sends a custom event. See :meth:`EngageClient.track`."""
        await self._send(
            self._build_event(
                event_name,
                properties,
                user_id=user_id,
                device_id=device_id,
                session_id=session_id,
                device_info=device_info,
                location=location,
                event_time=event_time,
            )
        )

    async def page(
        self,
        properties: Mapping[str, Any] | None = None,
        *,
        user_id: str | None = None,
        device_id: str | None = None,
        session_id: str | None = None,
        device_info: DeviceInfo | None = None,
        location: LocationInfo | None = None,
        event_time: datetime | None = None,
    ) -> None:
        """Sends a ``page_view`` event. See :meth:`EngageClient.page`."""
        await self._send(
            self._build_event(
                PAGE_VIEW_EVENT,
                properties,
                user_id=user_id,
                device_id=device_id,
                session_id=session_id,
                device_info=device_info,
                location=location,
                event_time=event_time,
            )
        )

    async def identify_user(
        self,
        user_id: str,
        properties: Mapping[str, Any] | None = None,
        *,
        device_id: str | None = None,
        session_id: str | None = None,
        device_info: DeviceInfo | None = None,
        location: LocationInfo | None = None,
        event_time: datetime | None = None,
    ) -> None:
        """Sends an ``_lowco_identify`` event. See :meth:`EngageClient.identify_user`."""
        if not user_id or not user_id.strip():
            raise ValueError("user_id is required")
        await self._send(
            self._build_event(
                IDENTIFY_EVENT,
                properties,
                user_id=user_id,
                device_id=device_id,
                session_id=session_id,
                device_info=device_info,
                location=location,
                event_time=event_time,
            )
        )

    async def _send(self, event: Event) -> None:
        resp = await self._http.post(
            self._track_url,
            content=encode_event(event),
            headers=self._headers,
            timeout=self._timeout,
        )
        check_status(resp.status_code, resp.text)
