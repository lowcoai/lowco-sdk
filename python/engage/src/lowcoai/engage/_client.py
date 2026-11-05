from __future__ import annotations

from collections.abc import Mapping, Sequence
from datetime import datetime
from typing import Any, cast

import httpx
from typing_extensions import Self

from ._base import (
    DEFAULT_TIMEOUT,
    IDENTIFY_EVENT,
    PAGE_VIEW_EVENT,
    BaseClient,
    check_status,
    decode_data,
    encode_event,
)
from .types import (
    AliasResult,
    BatchResult,
    ConsentResult,
    DeviceInfo,
    Event,
    JourneyParticipant,
    LocationInfo,
    Profile,
)

__all__ = ["AsyncEngageClient", "EngageClient"]


class EngageClient(BaseClient):
    """Server-side client for the lowco engage track API.

    Every call sends one event to ``POST https://api.lowco.ai/v1/engage/track``
    with the credential (``X-Api-Key`` for an ``lc_`` API key, otherwise
    ``Authorization: Bearer``), ``X-Org-Id: <org_id>`` and, when ``app_id`` is
    set, ``X-Engage-App-Id: <app_id>``.

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
        app_id: str | None = None,
        device_id: str | None = None,
        timeout: float | None = DEFAULT_TIMEOUT,
        http_client: httpx.Client | None = None,
        base_url: str | None = None,
    ) -> None:
        """
        Args:
            api_key: Credential. Required. An ``lc_`` API key is sent as
                ``X-Api-Key``; anything else (an OAuth2 access token) as
                ``Authorization: Bearer <api_key>``.
            org_id: Organisation id, sent as the ``X-Org-Id`` header. Required.
            app_id: Engage app to track into, sent as ``X-Engage-App-Id``.
                Optional: without it events go to the org's default app.
            device_id: Default ``device_id`` for events that don't pass one.
                Defaults to a uuid4 generated for this client instance.
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
            http_client: Custom ``httpx.Client`` (proxies, retries, mocks). It is
                not closed by :meth:`close`.
            base_url: Replaces ``https://api.lowco.ai`` (a staging host, say).
        """
        super().__init__(api_key, org_id, app_id=app_id, device_id=device_id, base_url=base_url)
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

    def track_batch(self, events: Sequence[Event]) -> BatchResult:
        """Sends up to 1000 events in one ``POST /v1/engage/track/batch``.

        Build the events with :meth:`build_event`. Unlike :meth:`track`, one bad
        event doesn't fail the rest: the result lists each event's outcome by
        its place (``results[i]["ok"]``, ``"error"``, ``"issues"``). Raises
        ``ValueError`` for no events or more than 1000 (before sending) and
        :class:`EngageError` when the whole batch is refused.
        """
        return cast(BatchResult, self._request(*self._batch_request(events)))

    def alias(self, user_id: str, alias_type: str, alias_value: str) -> AliasResult:
        """Records another name for a person (``ALIAS_ANONYMOUS``, ``ALIAS_EMAIL``,
        ``ALIAS_PHONE`` or ``ALIAS_EXTERNAL``).

        An alias another person already holds stays theirs: ``claimed`` is
        ``False`` and ``heldBy`` names them. Needs a server (admin) credential.
        """
        request = self._alias_request(user_id, alias_type, alias_value)
        return cast(AliasResult, self._request(*request))

    def merge(self, keep_user_id: str, merge_user_id: str) -> Profile:
        """Merges ``merge_user_id``'s profile into ``keep_user_id``'s; returns the kept one.

        Its traits fill the kept profile's blanks, the stricter consent wins on
        each channel, and its aliases, events and history move over. A 202
        answer (merged, the event store catching up) is success too. Needs a
        server (admin) credential.
        """
        request = self._merge_request(keep_user_id, merge_user_id)
        return cast(Profile, self._request(*request) or {})

    def set_consent(
        self,
        user_id: str,
        channel: str,
        status: str,
        *,
        source: str | None = None,
        evidence: Mapping[str, Any] | None = None,
    ) -> ConsentResult:
        """Records a consent change (``CONSENT_OPTED_IN``, ``CONSENT_OPTED_OUT`` or
        ``CONSENT_PENDING``) on a channel (see ``CONSENT_CHANNELS``).

        ``source`` defaults to ``"api"`` on the service; ``evidence`` is kept with
        the change. Needs a server (admin) credential.
        """
        request = self._consent_request(user_id, channel, status, source, evidence)
        return cast(ConsentResult, self._request(*request))

    def enter_journey(self, journey_id: str, user_id: str) -> JourneyParticipant:
        """Puts a person in a journey and returns their participant record.

        Raises :class:`EngageError` with ``status_code`` 409 when the person is
        in it already (or may not re-enter yet). Needs a server (admin) credential.
        """
        request = self._journey_request(journey_id, user_id)
        return cast(JourneyParticipant, self._request(*request))

    def _request(self, method: str, url: str, body: bytes) -> Any:
        resp = self._http.request(
            method, url, content=body, headers=self._headers, timeout=self._timeout
        )
        return decode_data(resp.status_code, resp.text)


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
        app_id: str | None = None,
        device_id: str | None = None,
        timeout: float | None = DEFAULT_TIMEOUT,
        http_client: httpx.AsyncClient | None = None,
        base_url: str | None = None,
    ) -> None:
        """
        Args:
            api_key: Credential. Required. An ``lc_`` API key is sent as
                ``X-Api-Key``; anything else (an OAuth2 access token) as
                ``Authorization: Bearer <api_key>``.
            org_id: Organisation id, sent as the ``X-Org-Id`` header. Required.
            app_id: Engage app to track into, sent as ``X-Engage-App-Id``.
                Optional: without it events go to the org's default app.
            device_id: Default ``device_id`` for events that don't pass one.
                Defaults to a uuid4 generated for this client instance.
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
            http_client: Custom ``httpx.AsyncClient`` (proxies, retries, mocks). It is
                not closed by :meth:`aclose`.
            base_url: Replaces ``https://api.lowco.ai`` (a staging host, say).
        """
        super().__init__(api_key, org_id, app_id=app_id, device_id=device_id, base_url=base_url)
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

    async def track_batch(self, events: Sequence[Event]) -> BatchResult:
        """Sends up to 1000 events in one request. See :meth:`EngageClient.track_batch`."""
        return cast(BatchResult, await self._request(*self._batch_request(events)))

    async def alias(self, user_id: str, alias_type: str, alias_value: str) -> AliasResult:
        """Records another name for a person. See :meth:`EngageClient.alias`."""
        request = self._alias_request(user_id, alias_type, alias_value)
        return cast(AliasResult, await self._request(*request))

    async def merge(self, keep_user_id: str, merge_user_id: str) -> Profile:
        """Merges two profiles. See :meth:`EngageClient.merge`."""
        request = self._merge_request(keep_user_id, merge_user_id)
        return cast(Profile, await self._request(*request) or {})

    async def set_consent(
        self,
        user_id: str,
        channel: str,
        status: str,
        *,
        source: str | None = None,
        evidence: Mapping[str, Any] | None = None,
    ) -> ConsentResult:
        """Records a consent change. See :meth:`EngageClient.set_consent`."""
        request = self._consent_request(user_id, channel, status, source, evidence)
        return cast(ConsentResult, await self._request(*request))

    async def enter_journey(self, journey_id: str, user_id: str) -> JourneyParticipant:
        """Puts a person in a journey. See :meth:`EngageClient.enter_journey`."""
        request = self._journey_request(journey_id, user_id)
        return cast(JourneyParticipant, await self._request(*request))

    async def _request(self, method: str, url: str, body: bytes) -> Any:
        resp = await self._http.request(
            method, url, content=body, headers=self._headers, timeout=self._timeout
        )
        return decode_data(resp.status_code, resp.text)
