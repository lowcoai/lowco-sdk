from __future__ import annotations

from collections.abc import Mapping
from datetime import datetime
from typing import Any

import httpx
from typing_extensions import Self

from ._base import (
    DEFAULT_TIMEOUT,
    BaseClient,
    check_status,
    decode_response,
    iso,
    list_query,
)
from .types import (
    Base,
    Column,
    ColumnsBulkResult,
    CountResponse,
    DashboardResponse,
    DBFunction,
    DBFunctionUpsertInput,
    DBFunctionVersion,
    DeleteCountResponse,
    Field,
    FunctionExecuteResult,
    FunctionHTTPMethod,
    LowcodbRecord,
    OverviewCounts,
    PublishEventInput,
    PublishEventResult,
    RecordsBulkResult,
    RowsResponse,
    RunQueryRequest,
    SuggestionsResponse,
    SyncTablesResult,
    Table,
    TableIndex,
    TableIndexUpdateInput,
    TableTrigger,
    TableView,
    TableWebhook,
    TableWithColumns,
    TransactionOperation,
    TransactionResult,
    ValidationResponse,
    ViewRefreshResponse,
)

__all__ = ["AsyncLowcodbClient", "LowcodbClient"]


class LowcodbClient(BaseClient):
    """Client for the lowcodb manager.

    ``token`` (a user token or API key) is required and sent as
    ``Authorization: Bearer <token>`` on every request. Use it as a context
    manager, or call :meth:`close`, to release the underlying connection pool.
    """

    def __init__(
        self,
        token: str,
        *,
        org_id: str | None = None,
        base_url: str | None = None,
        api_base_path: str | None = None,
        default_headers: Mapping[str, str] | None = None,
        timeout: float | None = DEFAULT_TIMEOUT,
        http_client: httpx.Client | None = None,
    ) -> None:
        """
        Args:
            token: User token or API key. Required.
            org_id: ``X-Org-Id`` header value.
            base_url: Origin of the lowcodb manager, e.g.
                ``"http://lowcodb-service:8080"`` for in-cluster callers.
                Defaults to ``"https://api.lowco.ai"``.
            api_base_path: Route prefix; defaults to ``"/v1/lowcodb"``.
            default_headers: Extra headers added to every request.
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
            http_client: Custom ``httpx.Client`` (proxies, retries, mocks). It is
                not closed by :meth:`close`.
        """
        super().__init__(
            token,
            org_id=org_id,
            base_url=base_url,
            api_base_path=api_base_path,
            default_headers=default_headers,
        )
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

    # --- Health ------------------------------------------------------------

    def health(self) -> None:
        self._request_void("GET", "/health")

    # --- Bases -------------------------------------------------------------

    def get_base(self, id: str) -> Base:
        return self._request("GET", self._api("bases", id))

    def create_base(self, base: Base) -> Base:
        return self._request("POST", self._api("bases"), body=base)

    def update_base(self, id: str, base: Base) -> Base:
        return self._request("PUT", self._api("bases", id), body=base)

    def delete_base(self, id: str) -> None:
        self._request_void("DELETE", self._api("bases", id))

    def list_bases(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[Base]:
        return self._request(
            "GET", self._api("bases"), query=list_query(page_no, size, filter, sort)
        )

    def export_base_collection(self, id: str) -> bytes:
        """Returns the base's Postman collection as raw bytes."""
        return self._request_raw("GET", self._api("bases", id, "export"))

    def sync_base_tables(self, id: str) -> SyncTablesResult:
        return self._request("POST", self._api("bases", id, "sync-tables"))

    # --- Tables ------------------------------------------------------------

    def get_table(self, id: str) -> TableWithColumns:
        return self._request("GET", self._api("tables", id))

    def create_table(self, table: Table) -> TableWithColumns:
        return self._request("POST", self._api("tables"), body=table)

    def update_table(self, id: str, table: Table) -> TableWithColumns:
        return self._request("PUT", self._api("tables", id), body=table)

    def delete_table(self, id: str) -> None:
        self._request_void("DELETE", self._api("tables", id))

    def list_tables(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[Table]:
        return self._request(
            "GET", self._api("tables"), query=list_query(page_no, size, filter, sort)
        )

    # --- Columns -----------------------------------------------------------

    def get_column(self, table_id: str, id: str) -> Column:
        return self._request("GET", self._api("tables", table_id, "columns", id))

    def create_column(self, table_id: str, column: Column) -> Column:
        return self._request("POST", self._api("tables", table_id, "columns"), body=column)

    def bulk_create_columns(self, table_id: str, columns: list[Column]) -> ColumnsBulkResult:
        return self._request("POST", self._api("tables", table_id, "columns", "bulk"), body=columns)

    def update_column(self, table_id: str, id: str, column: Column) -> Column:
        return self._request("PUT", self._api("tables", table_id, "columns", id), body=column)

    def bulk_update_columns(self, table_id: str, columns: list[Column]) -> dict[str, Any]:
        return self._request("PUT", self._api("tables", table_id, "columns", "bulk"), body=columns)

    def delete_column(self, table_id: str, id: str) -> None:
        self._request_void("DELETE", self._api("tables", table_id, "columns", id))

    def list_columns(
        self,
        table_id: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[Column]:
        return self._request(
            "GET",
            self._api("tables", table_id, "columns"),
            query=list_query(page_no, size, filter, sort),
        )

    def validate_field(self, field: Field) -> ValidationResponse:
        """Runs the manager's field validator without persisting anything."""
        return self._request("POST", self._api("validate"), body=field, enveloped=False)

    # --- Table indexes -----------------------------------------------------

    def get_table_index(self, table_id: str, id: str) -> TableIndex:
        return self._request("GET", self._api("tables", table_id, "index", id))

    def create_table_index(self, table_id: str, index: TableIndex) -> TableIndex:
        return self._request("POST", self._api("tables", table_id, "index"), body=index)

    def update_table_index(
        self, table_id: str, id: str, index: TableIndexUpdateInput
    ) -> TableIndex:
        return self._request("PUT", self._api("tables", table_id, "index", id), body=index)

    def list_table_indexes(
        self,
        table_id: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[TableIndex]:
        return self._request(
            "GET",
            self._api("tables", table_id, "indexes"),
            query=list_query(page_no, size, filter, sort),
        )

    def delete_table_index(self, table_id: str, id: str) -> None:
        self._request_void("DELETE", self._api("tables", table_id, "index", id))

    # --- Records -----------------------------------------------------------

    def create_record(self, schema: str, table_name: str, record: LowcodbRecord) -> LowcodbRecord:
        return self._request(
            "POST", self._data(schema, "tables", table_name, "records"), body=record
        )

    def get_record(self, schema: str, table_name: str, id: str) -> LowcodbRecord:
        return self._request("GET", self._data(schema, "tables", table_name, "records", id))

    def update_record(
        self, schema: str, table_name: str, id: str, record: LowcodbRecord
    ) -> LowcodbRecord:
        return self._request(
            "PUT", self._data(schema, "tables", table_name, "records", id), body=record
        )

    def delete_record(self, schema: str, table_name: str, id: str) -> DeleteCountResponse:
        return self._request("DELETE", self._data(schema, "tables", table_name, "records", id))

    def list_records(
        self,
        schema: str,
        table_name: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[LowcodbRecord]:
        return self._request(
            "GET",
            self._data(schema, "tables", table_name, "records"),
            query=list_query(page_no, size, filter, sort),
        )

    def count_records(
        self,
        schema: str,
        table_name: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> CountResponse:
        return self._request(
            "GET",
            self._data(schema, "tables", table_name, "records", "count"),
            query=list_query(page_no, size, filter, sort),
        )

    def create_bulk_records(
        self, schema: str, table_name: str, records: list[LowcodbRecord]
    ) -> None:
        self._request_void(
            "POST", self._data(schema, "tables", table_name, "records", "bulk"), body=records
        )

    def update_bulk_records(
        self, schema: str, table_name: str, records: list[LowcodbRecord]
    ) -> RecordsBulkResult:
        return self._request(
            "PUT", self._data(schema, "tables", table_name, "records", "bulk"), body=records
        )

    def delete_bulk_records(self, schema: str, table_name: str, body: Any) -> None:
        """Bulk delete. The manager treats ``body`` as the deletion criterion
        (typically a list of ids or a filter clause)."""
        self._request_void(
            "DELETE", self._data(schema, "tables", table_name, "records", "bulk"), body=body
        )

    # --- View data ---------------------------------------------------------

    def get_view_record(self, schema: str, view_name: str, id: str) -> LowcodbRecord:
        return self._request("GET", self._data(schema, "views", view_name, "records", id))

    def list_view_records(
        self,
        schema: str,
        view_name: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[LowcodbRecord]:
        return self._request(
            "GET",
            self._data(schema, "views", view_name, "records"),
            query=list_query(page_no, size, filter, sort),
        )

    def count_view_records(
        self,
        schema: str,
        view_name: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> CountResponse:
        return self._request(
            "GET",
            self._data(schema, "views", view_name, "records", "count"),
            query=list_query(page_no, size, filter, sort),
        )

    # --- Overview / dashboards --------------------------------------------

    def get_overview_counts(self) -> OverviewCounts:
        return self._request("GET", self._api("overview", "counts"))

    def get_metrics_dashboard(
        self,
        *,
        range: str | None = None,
        from_: datetime | None = None,
        to: datetime | None = None,
        base_id: str | None = None,
    ) -> DashboardResponse:
        """``range`` is a Go duration string, e.g. ``"5m"`` or ``"24h"``."""
        q: dict[str, str] = {}
        if range:
            q["range"] = range
        if from_:
            q["from"] = iso(from_)
        if to:
            q["to"] = iso(to)
        if base_id:
            q["baseId"] = base_id
        return self._request("GET", self._api("metrics", "dashboard"), query=q)

    def get_dashboard_overview(
        self,
        *,
        base_id: str | None = None,
        table_id: str | None = None,
        start_date: datetime | None = None,
        end_date: datetime | None = None,
    ) -> DashboardResponse:
        q: dict[str, str] = {}
        if base_id:
            q["baseId"] = base_id
        if table_id:
            q["tableId"] = table_id
        if start_date:
            q["startDate"] = iso(start_date)
        if end_date:
            q["endDate"] = iso(end_date)
        return self._request("GET", self._api("dashboard", "overview"), query=q)

    # --- Triggers ----------------------------------------------------------

    def get_trigger(self, id: str) -> TableTrigger:
        return self._request("GET", self._api("triggers", id))

    def create_trigger(self, trigger: TableTrigger) -> TableTrigger:
        return self._request("POST", self._api("triggers"), body=trigger)

    def update_trigger(self, id: str, trigger: TableTrigger) -> TableTrigger:
        return self._request("PUT", self._api("triggers", id), body=trigger)

    def delete_trigger(self, id: str) -> None:
        self._request_void("DELETE", self._api("triggers", id))

    def list_triggers(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[TableTrigger]:
        return self._request(
            "GET", self._api("triggers"), query=list_query(page_no, size, filter, sort)
        )

    # --- Webhooks ----------------------------------------------------------

    def get_webhook(self, id: str) -> TableWebhook:
        return self._request("GET", self._api("webhooks", id))

    def create_webhook(self, webhook: TableWebhook) -> TableWebhook:
        return self._request("POST", self._api("webhooks"), body=webhook)

    def update_webhook(self, id: str, webhook: TableWebhook) -> TableWebhook:
        return self._request("PUT", self._api("webhooks", id), body=webhook)

    def delete_webhook(self, id: str) -> None:
        self._request_void("DELETE", self._api("webhooks", id))

    def list_webhooks(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[TableWebhook]:
        return self._request(
            "GET", self._api("webhooks"), query=list_query(page_no, size, filter, sort)
        )

    # --- Transactions ------------------------------------------------------

    def execute_transaction(
        self, schema: str, operations: list[TransactionOperation]
    ) -> TransactionResult:
        """Runs ordered create/update/delete record operations inside one
        database transaction — all succeed or none apply. Internal bases only."""
        return self._request(
            "POST", self._api("data", schema, "transactions"), body={"operations": operations}
        )

    # --- Events ------------------------------------------------------------

    def publish_event(self, schema: str, input: PublishEventInput) -> PublishEventResult:
        """Publishes a data event for a base on the platform event bus."""
        return self._request(
            "POST", self._api("events", "publish"), body={"schema": schema, **input}
        )

    # --- DB Functions ------------------------------------------------------

    def list_functions(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[DBFunction]:
        return self._request(
            "GET", self._api("functions"), query=list_query(page_no, size, filter, sort)
        )

    def get_function(self, id: str) -> DBFunction:
        return self._request("GET", self._api("functions", id))

    def create_function(self, fn: DBFunctionUpsertInput) -> DBFunction:
        return self._request("POST", self._api("functions"), body=fn)

    def update_function(self, id: str, fn: DBFunctionUpsertInput) -> DBFunction:
        return self._request("PUT", self._api("functions", id), body=fn)

    def delete_function(self, id: str) -> None:
        self._request_void("DELETE", self._api("functions", id))

    def list_function_versions(self, id: str) -> list[DBFunctionVersion]:
        return self._request("GET", self._api("functions", id, "versions"))

    def execute_function(self, id: str, body: Any = None) -> FunctionExecuteResult:
        """Console/test execution: runs the function (active or not) with ``body``
        surfaced as ``ctx.request.body`` and returns the full result including
        logs and any function error."""
        return self._request(
            "POST", self._api("functions", id, "execute"), body={} if body is None else body
        )

    def invoke_function(
        self,
        schema: str,
        function_key: str,
        body: Any = None,
        *,
        method: FunctionHTTPMethod = "POST",
    ) -> Any:
        """Data-plane invocation of an active function by schema + key (the same
        route the base's gateway proxies ``/v1/fn/{key}`` to). Returns the
        function's return value."""
        return self._request(method, self._api("fn", schema, function_key), body=body)

    # --- Query -------------------------------------------------------------

    def execute_query(self, req: RunQueryRequest) -> RowsResponse:
        return self._request("POST", self._api("query", "execute"), body=req)

    def get_query_suggestions(self, query: str, base_id: str | None = None) -> SuggestionsResponse:
        q = {"query": query}
        if base_id:
            q["baseId"] = base_id
        return self._request("GET", self._api("query", "suggestions"), query=q)

    # --- Views (metadata) --------------------------------------------------

    def list_views(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[TableView]:
        return self._request(
            "GET", self._api("views"), query=list_query(page_no, size, filter, sort)
        )

    def create_view(self, view: TableView) -> TableView:
        return self._request("POST", self._api("views"), body=view)

    def get_view(self, id: str) -> TableView:
        return self._request("GET", self._api("views", id))

    def update_view(self, id: str, view: TableView) -> TableView:
        return self._request("PUT", self._api("views", id), body=view)

    def delete_view(self, id: str) -> None:
        self._request_void("DELETE", self._api("views", id))

    def refresh_view(self, id: str, *, concurrent: bool = False) -> ViewRefreshResponse:
        return self._request(
            "POST", self._api("views", id, "refresh"), body={"concurrent": concurrent}
        )

    # --- internals ---------------------------------------------------------

    def _send(
        self, method: str, path: str, query: dict[str, str] | None, body: Any
    ) -> httpx.Response:
        content = self._encode_body(body)
        return self._http.request(
            method,
            self._url(path),
            params=query or None,
            content=content,
            headers=self._request_headers(content is not None),
            timeout=self._timeout,
        )

    def _request(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, str] | None = None,
        body: Any = None,
        enveloped: bool = True,
    ) -> Any:
        resp = self._send(method, path, query, body)
        return decode_response(resp.status_code, resp.text, enveloped=enveloped)

    def _request_void(self, method: str, path: str, *, body: Any = None) -> None:
        resp = self._send(method, path, None, body)
        check_status(resp.status_code, resp.text)

    def _request_raw(self, method: str, path: str) -> bytes:
        resp = self._send(method, path, None, None)
        check_status(resp.status_code, resp.text)
        return resp.content


class AsyncLowcodbClient(BaseClient):
    """Asyncio client for the lowcodb manager (same surface as :class:`LowcodbClient`).

    ``token`` (a user token or API key) is required and sent as
    ``Authorization: Bearer <token>`` on every request. Use it as an async context
    manager, or call :meth:`aclose`, to release the underlying connection pool.
    """

    def __init__(
        self,
        token: str,
        *,
        org_id: str | None = None,
        base_url: str | None = None,
        api_base_path: str | None = None,
        default_headers: Mapping[str, str] | None = None,
        timeout: float | None = DEFAULT_TIMEOUT,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        """
        Args:
            token: User token or API key. Required.
            org_id: ``X-Org-Id`` header value.
            base_url: Origin of the lowcodb manager, e.g.
                ``"http://lowcodb-service:8080"`` for in-cluster callers.
                Defaults to ``"https://api.lowco.ai"``.
            api_base_path: Route prefix; defaults to ``"/v1/lowcodb"``.
            default_headers: Extra headers added to every request.
            timeout: Per-request timeout in seconds (default 30). ``None`` disables it.
            http_client: Custom ``httpx.AsyncClient`` (proxies, retries, mocks). It is
                not closed by :meth:`aclose`.
        """
        super().__init__(
            token,
            org_id=org_id,
            base_url=base_url,
            api_base_path=api_base_path,
            default_headers=default_headers,
        )
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

    # --- Health ------------------------------------------------------------

    async def health(self) -> None:
        await self._request_void("GET", "/health")

    # --- Bases -------------------------------------------------------------

    async def get_base(self, id: str) -> Base:
        return await self._request("GET", self._api("bases", id))

    async def create_base(self, base: Base) -> Base:
        return await self._request("POST", self._api("bases"), body=base)

    async def update_base(self, id: str, base: Base) -> Base:
        return await self._request("PUT", self._api("bases", id), body=base)

    async def delete_base(self, id: str) -> None:
        await self._request_void("DELETE", self._api("bases", id))

    async def list_bases(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[Base]:
        return await self._request(
            "GET", self._api("bases"), query=list_query(page_no, size, filter, sort)
        )

    async def export_base_collection(self, id: str) -> bytes:
        """Returns the base's Postman collection as raw bytes."""
        return await self._request_raw("GET", self._api("bases", id, "export"))

    async def sync_base_tables(self, id: str) -> SyncTablesResult:
        return await self._request("POST", self._api("bases", id, "sync-tables"))

    # --- Tables ------------------------------------------------------------

    async def get_table(self, id: str) -> TableWithColumns:
        return await self._request("GET", self._api("tables", id))

    async def create_table(self, table: Table) -> TableWithColumns:
        return await self._request("POST", self._api("tables"), body=table)

    async def update_table(self, id: str, table: Table) -> TableWithColumns:
        return await self._request("PUT", self._api("tables", id), body=table)

    async def delete_table(self, id: str) -> None:
        await self._request_void("DELETE", self._api("tables", id))

    async def list_tables(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[Table]:
        return await self._request(
            "GET", self._api("tables"), query=list_query(page_no, size, filter, sort)
        )

    # --- Columns -----------------------------------------------------------

    async def get_column(self, table_id: str, id: str) -> Column:
        return await self._request("GET", self._api("tables", table_id, "columns", id))

    async def create_column(self, table_id: str, column: Column) -> Column:
        return await self._request("POST", self._api("tables", table_id, "columns"), body=column)

    async def bulk_create_columns(self, table_id: str, columns: list[Column]) -> ColumnsBulkResult:
        return await self._request(
            "POST", self._api("tables", table_id, "columns", "bulk"), body=columns
        )

    async def update_column(self, table_id: str, id: str, column: Column) -> Column:
        return await self._request("PUT", self._api("tables", table_id, "columns", id), body=column)

    async def bulk_update_columns(self, table_id: str, columns: list[Column]) -> dict[str, Any]:
        return await self._request(
            "PUT", self._api("tables", table_id, "columns", "bulk"), body=columns
        )

    async def delete_column(self, table_id: str, id: str) -> None:
        await self._request_void("DELETE", self._api("tables", table_id, "columns", id))

    async def list_columns(
        self,
        table_id: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[Column]:
        return await self._request(
            "GET",
            self._api("tables", table_id, "columns"),
            query=list_query(page_no, size, filter, sort),
        )

    async def validate_field(self, field: Field) -> ValidationResponse:
        """Runs the manager's field validator without persisting anything."""
        return await self._request("POST", self._api("validate"), body=field, enveloped=False)

    # --- Table indexes -----------------------------------------------------

    async def get_table_index(self, table_id: str, id: str) -> TableIndex:
        return await self._request("GET", self._api("tables", table_id, "index", id))

    async def create_table_index(self, table_id: str, index: TableIndex) -> TableIndex:
        return await self._request("POST", self._api("tables", table_id, "index"), body=index)

    async def update_table_index(
        self, table_id: str, id: str, index: TableIndexUpdateInput
    ) -> TableIndex:
        return await self._request("PUT", self._api("tables", table_id, "index", id), body=index)

    async def list_table_indexes(
        self,
        table_id: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[TableIndex]:
        return await self._request(
            "GET",
            self._api("tables", table_id, "indexes"),
            query=list_query(page_no, size, filter, sort),
        )

    async def delete_table_index(self, table_id: str, id: str) -> None:
        await self._request_void("DELETE", self._api("tables", table_id, "index", id))

    # --- Records -----------------------------------------------------------

    async def create_record(
        self, schema: str, table_name: str, record: LowcodbRecord
    ) -> LowcodbRecord:
        return await self._request(
            "POST", self._data(schema, "tables", table_name, "records"), body=record
        )

    async def get_record(self, schema: str, table_name: str, id: str) -> LowcodbRecord:
        return await self._request("GET", self._data(schema, "tables", table_name, "records", id))

    async def update_record(
        self, schema: str, table_name: str, id: str, record: LowcodbRecord
    ) -> LowcodbRecord:
        return await self._request(
            "PUT", self._data(schema, "tables", table_name, "records", id), body=record
        )

    async def delete_record(self, schema: str, table_name: str, id: str) -> DeleteCountResponse:
        return await self._request(
            "DELETE", self._data(schema, "tables", table_name, "records", id)
        )

    async def list_records(
        self,
        schema: str,
        table_name: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[LowcodbRecord]:
        return await self._request(
            "GET",
            self._data(schema, "tables", table_name, "records"),
            query=list_query(page_no, size, filter, sort),
        )

    async def count_records(
        self,
        schema: str,
        table_name: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> CountResponse:
        return await self._request(
            "GET",
            self._data(schema, "tables", table_name, "records", "count"),
            query=list_query(page_no, size, filter, sort),
        )

    async def create_bulk_records(
        self, schema: str, table_name: str, records: list[LowcodbRecord]
    ) -> None:
        await self._request_void(
            "POST", self._data(schema, "tables", table_name, "records", "bulk"), body=records
        )

    async def update_bulk_records(
        self, schema: str, table_name: str, records: list[LowcodbRecord]
    ) -> RecordsBulkResult:
        return await self._request(
            "PUT", self._data(schema, "tables", table_name, "records", "bulk"), body=records
        )

    async def delete_bulk_records(self, schema: str, table_name: str, body: Any) -> None:
        """Bulk delete. The manager treats ``body`` as the deletion criterion
        (typically a list of ids or a filter clause)."""
        await self._request_void(
            "DELETE", self._data(schema, "tables", table_name, "records", "bulk"), body=body
        )

    # --- View data ---------------------------------------------------------

    async def get_view_record(self, schema: str, view_name: str, id: str) -> LowcodbRecord:
        return await self._request("GET", self._data(schema, "views", view_name, "records", id))

    async def list_view_records(
        self,
        schema: str,
        view_name: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[LowcodbRecord]:
        return await self._request(
            "GET",
            self._data(schema, "views", view_name, "records"),
            query=list_query(page_no, size, filter, sort),
        )

    async def count_view_records(
        self,
        schema: str,
        view_name: str,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> CountResponse:
        return await self._request(
            "GET",
            self._data(schema, "views", view_name, "records", "count"),
            query=list_query(page_no, size, filter, sort),
        )

    # --- Overview / dashboards --------------------------------------------

    async def get_overview_counts(self) -> OverviewCounts:
        return await self._request("GET", self._api("overview", "counts"))

    async def get_metrics_dashboard(
        self,
        *,
        range: str | None = None,
        from_: datetime | None = None,
        to: datetime | None = None,
        base_id: str | None = None,
    ) -> DashboardResponse:
        """``range`` is a Go duration string, e.g. ``"5m"`` or ``"24h"``."""
        q: dict[str, str] = {}
        if range:
            q["range"] = range
        if from_:
            q["from"] = iso(from_)
        if to:
            q["to"] = iso(to)
        if base_id:
            q["baseId"] = base_id
        return await self._request("GET", self._api("metrics", "dashboard"), query=q)

    async def get_dashboard_overview(
        self,
        *,
        base_id: str | None = None,
        table_id: str | None = None,
        start_date: datetime | None = None,
        end_date: datetime | None = None,
    ) -> DashboardResponse:
        q: dict[str, str] = {}
        if base_id:
            q["baseId"] = base_id
        if table_id:
            q["tableId"] = table_id
        if start_date:
            q["startDate"] = iso(start_date)
        if end_date:
            q["endDate"] = iso(end_date)
        return await self._request("GET", self._api("dashboard", "overview"), query=q)

    # --- Triggers ----------------------------------------------------------

    async def get_trigger(self, id: str) -> TableTrigger:
        return await self._request("GET", self._api("triggers", id))

    async def create_trigger(self, trigger: TableTrigger) -> TableTrigger:
        return await self._request("POST", self._api("triggers"), body=trigger)

    async def update_trigger(self, id: str, trigger: TableTrigger) -> TableTrigger:
        return await self._request("PUT", self._api("triggers", id), body=trigger)

    async def delete_trigger(self, id: str) -> None:
        await self._request_void("DELETE", self._api("triggers", id))

    async def list_triggers(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[TableTrigger]:
        return await self._request(
            "GET", self._api("triggers"), query=list_query(page_no, size, filter, sort)
        )

    # --- Webhooks ----------------------------------------------------------

    async def get_webhook(self, id: str) -> TableWebhook:
        return await self._request("GET", self._api("webhooks", id))

    async def create_webhook(self, webhook: TableWebhook) -> TableWebhook:
        return await self._request("POST", self._api("webhooks"), body=webhook)

    async def update_webhook(self, id: str, webhook: TableWebhook) -> TableWebhook:
        return await self._request("PUT", self._api("webhooks", id), body=webhook)

    async def delete_webhook(self, id: str) -> None:
        await self._request_void("DELETE", self._api("webhooks", id))

    async def list_webhooks(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[TableWebhook]:
        return await self._request(
            "GET", self._api("webhooks"), query=list_query(page_no, size, filter, sort)
        )

    # --- Transactions ------------------------------------------------------

    async def execute_transaction(
        self, schema: str, operations: list[TransactionOperation]
    ) -> TransactionResult:
        """Runs ordered create/update/delete record operations inside one
        database transaction — all succeed or none apply. Internal bases only."""
        return await self._request(
            "POST", self._api("data", schema, "transactions"), body={"operations": operations}
        )

    # --- Events ------------------------------------------------------------

    async def publish_event(self, schema: str, input: PublishEventInput) -> PublishEventResult:
        """Publishes a data event for a base on the platform event bus."""
        return await self._request(
            "POST", self._api("events", "publish"), body={"schema": schema, **input}
        )

    # --- DB Functions ------------------------------------------------------

    async def list_functions(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[DBFunction]:
        return await self._request(
            "GET", self._api("functions"), query=list_query(page_no, size, filter, sort)
        )

    async def get_function(self, id: str) -> DBFunction:
        return await self._request("GET", self._api("functions", id))

    async def create_function(self, fn: DBFunctionUpsertInput) -> DBFunction:
        return await self._request("POST", self._api("functions"), body=fn)

    async def update_function(self, id: str, fn: DBFunctionUpsertInput) -> DBFunction:
        return await self._request("PUT", self._api("functions", id), body=fn)

    async def delete_function(self, id: str) -> None:
        await self._request_void("DELETE", self._api("functions", id))

    async def list_function_versions(self, id: str) -> list[DBFunctionVersion]:
        return await self._request("GET", self._api("functions", id, "versions"))

    async def execute_function(self, id: str, body: Any = None) -> FunctionExecuteResult:
        """Console/test execution: runs the function (active or not) with ``body``
        surfaced as ``ctx.request.body`` and returns the full result including
        logs and any function error."""
        return await self._request(
            "POST", self._api("functions", id, "execute"), body={} if body is None else body
        )

    async def invoke_function(
        self,
        schema: str,
        function_key: str,
        body: Any = None,
        *,
        method: FunctionHTTPMethod = "POST",
    ) -> Any:
        """Data-plane invocation of an active function by schema + key (the same
        route the base's gateway proxies ``/v1/fn/{key}`` to). Returns the
        function's return value."""
        return await self._request(method, self._api("fn", schema, function_key), body=body)

    # --- Query -------------------------------------------------------------

    async def execute_query(self, req: RunQueryRequest) -> RowsResponse:
        return await self._request("POST", self._api("query", "execute"), body=req)

    async def get_query_suggestions(
        self, query: str, base_id: str | None = None
    ) -> SuggestionsResponse:
        q = {"query": query}
        if base_id:
            q["baseId"] = base_id
        return await self._request("GET", self._api("query", "suggestions"), query=q)

    # --- Views (metadata) --------------------------------------------------

    async def list_views(
        self,
        *,
        page_no: int | None = None,
        size: int | None = None,
        filter: str | None = None,
        sort: str | None = None,
    ) -> list[TableView]:
        return await self._request(
            "GET", self._api("views"), query=list_query(page_no, size, filter, sort)
        )

    async def create_view(self, view: TableView) -> TableView:
        return await self._request("POST", self._api("views"), body=view)

    async def get_view(self, id: str) -> TableView:
        return await self._request("GET", self._api("views", id))

    async def update_view(self, id: str, view: TableView) -> TableView:
        return await self._request("PUT", self._api("views", id), body=view)

    async def delete_view(self, id: str) -> None:
        await self._request_void("DELETE", self._api("views", id))

    async def refresh_view(self, id: str, *, concurrent: bool = False) -> ViewRefreshResponse:
        return await self._request(
            "POST", self._api("views", id, "refresh"), body={"concurrent": concurrent}
        )

    # --- internals ---------------------------------------------------------

    async def _send(
        self, method: str, path: str, query: dict[str, str] | None, body: Any
    ) -> httpx.Response:
        content = self._encode_body(body)
        return await self._http.request(
            method,
            self._url(path),
            params=query or None,
            content=content,
            headers=self._request_headers(content is not None),
            timeout=self._timeout,
        )

    async def _request(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, str] | None = None,
        body: Any = None,
        enveloped: bool = True,
    ) -> Any:
        resp = await self._send(method, path, query, body)
        return decode_response(resp.status_code, resp.text, enveloped=enveloped)

    async def _request_void(self, method: str, path: str, *, body: Any = None) -> None:
        resp = await self._send(method, path, None, body)
        check_status(resp.status_code, resp.text)

    async def _request_raw(self, method: str, path: str) -> bytes:
        resp = await self._send(method, path, None, None)
        check_status(resp.status_code, resp.text)
        return resp.content
