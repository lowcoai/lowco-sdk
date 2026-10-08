import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'json.dart';
import 'models.dart';

/// The fixed API host every lowco SDK talks to by default.
const String lowcoBaseUrl = 'https://api.lowco.ai';

/// Default route prefix of the lowcodb manager.
const String defaultApiBasePath = '/v1/lowcodb';

/// Header carrying the organization id.
const String headerOrgId = 'X-Org-Id';

/// Pagination / filtering accepted by every list endpoint.
class ListParams {
  const ListParams({this.pageNo, this.size, this.filter, this.sort});

  final int? pageNo;
  final int? size;
  final String? filter;
  final String? sort;

  Map<String, String> toQuery() => {
        if (pageNo != null) 'pageNo': '$pageNo',
        if (size != null) 'size': '$size',
        if (filter != null) 'filter': filter!,
        if (sort != null) 'sort': sort!,
      };
}

/// Client for the lowcodb manager.
///
/// [token] (a user token or API key) is required and sent as
/// `Authorization: Bearer <token>` on every request. Call [close] when done
/// to release the underlying HTTP client (unless you passed your own).
class LowcodbClient {
  /// Creates a client.
  ///
  /// * [orgId] — `X-Org-Id` header value.
  /// * [baseUrl] — origin of the manager, e.g. `http://lowcodb-service:8080`
  ///   for in-cluster callers. Defaults to `https://api.lowco.ai`.
  /// * [apiBasePath] — route prefix, default `/v1/lowcodb`.
  /// * [defaultHeaders] — extra headers added to every request.
  /// * [timeout] — per-request timeout (default 30 s); `null` disables it.
  /// * [httpClient] — custom `http.Client` (e.g. a `MockClient` in tests or a
  ///   platform client in Flutter). It is not closed by [close].
  LowcodbClient({
    required String token,
    String? orgId,
    String baseUrl = lowcoBaseUrl,
    String apiBasePath = defaultApiBasePath,
    Map<String, String>? defaultHeaders,
    Duration? timeout = const Duration(seconds: 30),
    http.Client? httpClient,
  })  : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _apiBasePath = _trimSlashes(apiBasePath),
        _timeout = timeout,
        _ownsHttp = httpClient == null,
        _http = httpClient ?? http.Client() {
    if (token.trim().isEmpty) {
      throw ArgumentError.value(token, 'token', 'LowcodbClient: token is required');
    }
    _headers
      ..addAll(defaultHeaders ?? const {})
      ..['Authorization'] = 'Bearer $token';
    if (orgId != null && orgId.isNotEmpty) _headers[headerOrgId] = orgId;
  }

  final String _baseUrl;
  final String _apiBasePath;
  final Duration? _timeout;
  final bool _ownsHttp;
  final http.Client _http;
  final Map<String, String> _headers = {};

  /// Sets the `X-Org-Id` header for later requests; `null` removes it.
  void setOrgId(String? orgId) {
    if (orgId != null && orgId.isNotEmpty) {
      _headers[headerOrgId] = orgId;
    } else {
      _headers.remove(headerOrgId);
    }
  }

  /// Sets / overwrites an arbitrary default header. Pass `null` to delete.
  void setHeader(String key, String? value) {
    if (value == null) {
      _headers.remove(key);
    } else {
      _headers[key] = value;
    }
  }

  /// Closes the underlying HTTP client if this instance created it.
  void close() {
    if (_ownsHttp) _http.close();
  }

  // --- Health --------------------------------------------------------------

  Future<void> health() => _requestVoid('GET', '/health');

  // --- Bases ---------------------------------------------------------------

  Future<Base> getBase(String id) async =>
      _one(await _request('GET', _api(['bases', id])), Base.fromJson);

  Future<Base> createBase(Base base) async =>
      _one(await _request('POST', _api(['bases']), body: base), Base.fromJson);

  Future<Base> updateBase(String id, Base base) async =>
      _one(await _request('PUT', _api(['bases', id]), body: base), Base.fromJson);

  Future<void> deleteBase(String id) => _requestVoid('DELETE', _api(['bases', id]));

  Future<List<Base>> listBases([ListParams? params]) async =>
      _many(await _request('GET', _api(['bases']), query: params?.toQuery()), Base.fromJson);

  /// The base's Postman collection as raw bytes.
  Future<Uint8List> exportBaseCollection(String id) =>
      _requestRaw('GET', _api(['bases', id, 'export']));

  Future<SyncTablesResult> syncBaseTables(String id) async =>
      _one(await _request('POST', _api(['bases', id, 'sync-tables'])), SyncTablesResult.fromJson);

  // --- Tables --------------------------------------------------------------

  Future<TableWithColumns> getTable(String id) async =>
      _one(await _request('GET', _api(['tables', id])), TableWithColumns.fromJson);

  Future<TableWithColumns> createTable(Table table) async =>
      _one(await _request('POST', _api(['tables']), body: table), TableWithColumns.fromJson);

  Future<TableWithColumns> updateTable(String id, Table table) async =>
      _one(await _request('PUT', _api(['tables', id]), body: table), TableWithColumns.fromJson);

  Future<void> deleteTable(String id) => _requestVoid('DELETE', _api(['tables', id]));

  Future<List<Table>> listTables([ListParams? params]) async =>
      _many(await _request('GET', _api(['tables']), query: params?.toQuery()), Table.fromJson);

  // --- Columns -------------------------------------------------------------

  Future<Column> getColumn(String tableId, String id) async =>
      _one(await _request('GET', _api(['tables', tableId, 'columns', id])), Column.fromJson);

  Future<Column> createColumn(String tableId, Column column) async => _one(
      await _request('POST', _api(['tables', tableId, 'columns']), body: column), Column.fromJson);

  Future<ColumnsBulkResult> bulkCreateColumns(String tableId, List<Column> columns) async => _one(
      await _request('POST', _api(['tables', tableId, 'columns', 'bulk']), body: columns),
      ColumnsBulkResult.fromJson);

  Future<Column> updateColumn(String tableId, String id, Column column) async => _one(
      await _request('PUT', _api(['tables', tableId, 'columns', id]), body: column),
      Column.fromJson);

  Future<Map<String, dynamic>> bulkUpdateColumns(String tableId, List<Column> columns) async =>
      _record(await _request('PUT', _api(['tables', tableId, 'columns', 'bulk']), body: columns));

  Future<void> deleteColumn(String tableId, String id) =>
      _requestVoid('DELETE', _api(['tables', tableId, 'columns', id]));

  Future<List<Column>> listColumns(String tableId, [ListParams? params]) async => _many(
      await _request('GET', _api(['tables', tableId, 'columns']), query: params?.toQuery()),
      Column.fromJson);

  /// Runs the manager's field validator without persisting anything.
  Future<ValidationResponse> validateField(Field field) async => _one(
      await _request('POST', _api(['validate']), body: field, enveloped: false),
      ValidationResponse.fromJson);

  // --- Table indexes -------------------------------------------------------

  Future<TableIndex> getTableIndex(String tableId, String id) async =>
      _one(await _request('GET', _api(['tables', tableId, 'index', id])), TableIndex.fromJson);

  Future<TableIndex> createTableIndex(String tableId, TableIndex index) async => _one(
      await _request('POST', _api(['tables', tableId, 'index']), body: index), TableIndex.fromJson);

  Future<TableIndex> updateTableIndex(
          String tableId, String id, TableIndexUpdateInput index) async =>
      _one(await _request('PUT', _api(['tables', tableId, 'index', id]), body: index),
          TableIndex.fromJson);

  Future<List<TableIndex>> listTableIndexes(String tableId, [ListParams? params]) async => _many(
      await _request('GET', _api(['tables', tableId, 'indexes']), query: params?.toQuery()),
      TableIndex.fromJson);

  Future<void> deleteTableIndex(String tableId, String id) =>
      _requestVoid('DELETE', _api(['tables', tableId, 'index', id]));

  // --- Records -------------------------------------------------------------

  Future<LowcodbRecord> createRecord(String schema, String tableName, LowcodbRecord record) async =>
      _record(
          await _request('POST', _data(schema, 'tables', tableName, ['records']), body: record));

  Future<LowcodbRecord> getRecord(String schema, String tableName, String id) async =>
      _record(await _request('GET', _data(schema, 'tables', tableName, ['records', id])));

  Future<LowcodbRecord> updateRecord(
          String schema, String tableName, String id, LowcodbRecord record) async =>
      _record(
          await _request('PUT', _data(schema, 'tables', tableName, ['records', id]), body: record));

  Future<DeleteCountResponse> deleteRecord(String schema, String tableName, String id) async =>
      _one(await _request('DELETE', _data(schema, 'tables', tableName, ['records', id])),
          DeleteCountResponse.fromJson);

  Future<List<LowcodbRecord>> listRecords(String schema, String tableName,
          [ListParams? params]) async =>
      _records(await _request('GET', _data(schema, 'tables', tableName, ['records']),
          query: params?.toQuery()));

  Future<CountResponse> countRecords(String schema, String tableName, [ListParams? params]) async =>
      _one(
          await _request('GET', _data(schema, 'tables', tableName, ['records', 'count']),
              query: params?.toQuery()),
          CountResponse.fromJson);

  Future<void> createBulkRecords(String schema, String tableName, List<LowcodbRecord> records) =>
      _requestVoid('POST', _data(schema, 'tables', tableName, ['records', 'bulk']), body: records);

  Future<RecordsBulkResult> updateBulkRecords(
          String schema, String tableName, List<LowcodbRecord> records) async =>
      _one(
          await _request('PUT', _data(schema, 'tables', tableName, ['records', 'bulk']),
              body: records),
          RecordsBulkResult.fromJson);

  /// Bulk delete. The manager treats [body] as the deletion criterion
  /// (typically a list of ids or a filter clause).
  Future<void> deleteBulkRecords(String schema, String tableName, Object? body) =>
      _requestVoid('DELETE', _data(schema, 'tables', tableName, ['records', 'bulk']), body: body);

  // --- View data -----------------------------------------------------------

  Future<LowcodbRecord> getViewRecord(String schema, String viewName, String id) async =>
      _record(await _request('GET', _data(schema, 'views', viewName, ['records', id])));

  Future<List<LowcodbRecord>> listViewRecords(String schema, String viewName,
          [ListParams? params]) async =>
      _records(await _request('GET', _data(schema, 'views', viewName, ['records']),
          query: params?.toQuery()));

  Future<CountResponse> countViewRecords(String schema, String viewName,
          [ListParams? params]) async =>
      _one(
          await _request('GET', _data(schema, 'views', viewName, ['records', 'count']),
              query: params?.toQuery()),
          CountResponse.fromJson);

  // --- Overview / dashboards -----------------------------------------------

  Future<OverviewCounts> getOverviewCounts() async =>
      _one(await _request('GET', _api(['overview', 'counts'])), OverviewCounts.fromJson);

  /// [range] is a Go duration string, e.g. `5m` or `24h`.
  Future<DashboardResponse> getMetricsDashboard(
      {String? range, DateTime? from, DateTime? to, String? baseId}) async {
    final q = <String, String>{
      if (range != null && range.isNotEmpty) 'range': range,
      if (from != null) 'from': _iso(from),
      if (to != null) 'to': _iso(to),
      if (baseId != null && baseId.isNotEmpty) 'baseId': baseId,
    };
    return _record(await _request('GET', _api(['metrics', 'dashboard']), query: q));
  }

  Future<DashboardResponse> getDashboardOverview(
      {String? baseId, String? tableId, DateTime? startDate, DateTime? endDate}) async {
    final q = <String, String>{
      if (baseId != null && baseId.isNotEmpty) 'baseId': baseId,
      if (tableId != null && tableId.isNotEmpty) 'tableId': tableId,
      if (startDate != null) 'startDate': _iso(startDate),
      if (endDate != null) 'endDate': _iso(endDate),
    };
    return _record(await _request('GET', _api(['dashboard', 'overview']), query: q));
  }

  // --- Triggers ------------------------------------------------------------

  Future<TableTrigger> getTrigger(String id) async =>
      _one(await _request('GET', _api(['triggers', id])), TableTrigger.fromJson);

  Future<TableTrigger> createTrigger(TableTrigger trigger) async =>
      _one(await _request('POST', _api(['triggers']), body: trigger), TableTrigger.fromJson);

  Future<TableTrigger> updateTrigger(String id, TableTrigger trigger) async =>
      _one(await _request('PUT', _api(['triggers', id]), body: trigger), TableTrigger.fromJson);

  Future<void> deleteTrigger(String id) => _requestVoid('DELETE', _api(['triggers', id]));

  Future<List<TableTrigger>> listTriggers([ListParams? params]) async => _many(
      await _request('GET', _api(['triggers']), query: params?.toQuery()), TableTrigger.fromJson);

  // --- Webhooks ------------------------------------------------------------

  Future<TableWebhook> getWebhook(String id) async =>
      _one(await _request('GET', _api(['webhooks', id])), TableWebhook.fromJson);

  Future<TableWebhook> createWebhook(TableWebhook webhook) async =>
      _one(await _request('POST', _api(['webhooks']), body: webhook), TableWebhook.fromJson);

  Future<TableWebhook> updateWebhook(String id, TableWebhook webhook) async =>
      _one(await _request('PUT', _api(['webhooks', id]), body: webhook), TableWebhook.fromJson);

  Future<void> deleteWebhook(String id) => _requestVoid('DELETE', _api(['webhooks', id]));

  Future<List<TableWebhook>> listWebhooks([ListParams? params]) async => _many(
      await _request('GET', _api(['webhooks']), query: params?.toQuery()), TableWebhook.fromJson);

  // --- Transactions --------------------------------------------------------

  /// Runs ordered create/update/delete record operations inside one database
  /// transaction — all succeed or none apply. Internal bases only.
  Future<TransactionResult> executeTransaction(
          String schema, List<TransactionOperation> operations) async =>
      _one(
          await _request('POST', _api(['data', schema, 'transactions']),
              body: {'operations': operations}),
          TransactionResult.fromJson);

  // --- Events --------------------------------------------------------------

  /// Publishes a data event for a base on the platform event bus.
  Future<PublishEventResult> publishEvent(String schema, PublishEventInput input) async => _one(
      await _request('POST', _api(['events', 'publish']),
          body: {'schema': schema, ...input.toJson()}),
      PublishEventResult.fromJson);

  // --- DB Functions --------------------------------------------------------

  Future<List<DBFunction>> listFunctions([ListParams? params]) async => _many(
      await _request('GET', _api(['functions']), query: params?.toQuery()), DBFunction.fromJson);

  Future<DBFunction> getFunction(String id) async =>
      _one(await _request('GET', _api(['functions', id])), DBFunction.fromJson);

  Future<DBFunction> createFunction(DBFunctionUpsertInput fn) async =>
      _one(await _request('POST', _api(['functions']), body: fn), DBFunction.fromJson);

  Future<DBFunction> updateFunction(String id, DBFunctionUpsertInput fn) async =>
      _one(await _request('PUT', _api(['functions', id]), body: fn), DBFunction.fromJson);

  Future<void> deleteFunction(String id) => _requestVoid('DELETE', _api(['functions', id]));

  Future<List<DBFunctionVersion>> listFunctionVersions(String id) async =>
      _many(await _request('GET', _api(['functions', id, 'versions'])), DBFunctionVersion.fromJson);

  /// Console/test execution: runs the function (active or not) with [body]
  /// surfaced as `ctx.request.body` and returns the full result including logs
  /// and any function error.
  Future<FunctionExecuteResult> executeFunction(String id, [Object? body]) async => _one(
      await _request('POST', _api(['functions', id, 'execute']), body: body ?? const {}),
      FunctionExecuteResult.fromJson);

  /// Data-plane invocation of an active function by schema + key (the same
  /// route the base's gateway proxies `/v1/fn/{key}` to). Resolves to the
  /// function's return value. [method] must be allowed by the function.
  Future<Object?> invokeFunction(String schema, String functionKey,
          {Object? body, String method = 'POST'}) =>
      _request(method, _api(['fn', schema, functionKey]), body: body);

  // --- Query ---------------------------------------------------------------

  Future<RowsResponse> executeQuery(RunQueryRequest req) async =>
      _one(await _request('POST', _api(['query', 'execute']), body: req), RowsResponse.fromJson);

  Future<SuggestionsResponse> getQuerySuggestions(String query, {String? baseId}) async => _one(
      await _request('GET', _api(['query', 'suggestions']), query: {
        'query': query,
        if (baseId != null && baseId.isNotEmpty) 'baseId': baseId,
      }),
      SuggestionsResponse.fromJson);

  // --- Views (metadata) ----------------------------------------------------

  Future<List<TableView>> listViews([ListParams? params]) async =>
      _many(await _request('GET', _api(['views']), query: params?.toQuery()), TableView.fromJson);

  Future<TableView> createView(TableView view) async =>
      _one(await _request('POST', _api(['views']), body: view), TableView.fromJson);

  Future<TableView> getView(String id) async =>
      _one(await _request('GET', _api(['views', id])), TableView.fromJson);

  Future<TableView> updateView(String id, TableView view) async =>
      _one(await _request('PUT', _api(['views', id]), body: view), TableView.fromJson);

  Future<void> deleteView(String id) => _requestVoid('DELETE', _api(['views', id]));

  Future<ViewRefreshResponse> refreshView(String id, {bool concurrent = false}) async => _one(
      await _request('POST', _api(['views', id, 'refresh']), body: {'concurrent': concurrent}),
      ViewRefreshResponse.fromJson);

  // --- internals -----------------------------------------------------------

  String _api(List<String> parts) =>
      '/${[_apiBasePath, ...parts.map((p) => Uri.encodeComponent(_trimSlashes(p)))].join('/')}';

  String _data(String schema, String objectType, String objectName, List<String> parts) => '/${[
        _apiBasePath,
        'data',
        Uri.encodeComponent(schema),
        objectType,
        Uri.encodeComponent(objectName),
        ...parts.map(Uri.encodeComponent),
      ].join('/')}';

  Future<http.Response> _send(String method, String path,
      {Map<String, String>? query, Object? body}) async {
    var url = Uri.parse('$_baseUrl$path');
    if (query != null && query.isNotEmpty) url = url.replace(queryParameters: query);

    final abort = Completer<void>();
    final req = http.AbortableRequest(method, url, abortTrigger: abort.future)
      ..headers.addAll({'Accept': 'application/json', ..._headers});
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body, toEncodable: _toEncodable);
    }

    final future = _http.send(req).then(http.Response.fromStream);
    final timeout = _timeout;
    if (timeout == null) return future;
    return future.timeout(timeout, onTimeout: () {
      // Abort the in-flight request where the platform client supports it.
      if (!abort.isCompleted) abort.complete();
      throw TimeoutException('lowcodb: $method $path timed out', timeout);
    });
  }

  Future<Object?> _request(String method, String path,
      {Map<String, String>? query, Object? body, bool enveloped = true}) async {
    final resp = await _send(method, path, query: query, body: body);
    return _decode(resp, enveloped: enveloped);
  }

  Future<void> _requestVoid(String method, String path, {Object? body}) async {
    final resp = await _send(method, path, body: body);
    _checkStatus(resp);
  }

  Future<Uint8List> _requestRaw(String method, String path) async {
    final resp = await _send(method, path);
    _checkStatus(resp);
    return resp.bodyBytes;
  }
}

String _trimSlashes(String s) => s.replaceAll(RegExp(r'^/+|/+$'), '');

String _iso(DateTime value) => value.toUtc().toIso8601String();

Object? _toEncodable(Object? value) {
  if (value is DateTime) return _iso(value);
  // Model classes expose toJson(); anything else is a caller error.
  return (value as dynamic).toJson();
}

String _text(http.Response resp) => utf8.decode(resp.bodyBytes, allowMalformed: true);

void _checkStatus(http.Response resp) {
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw buildHttpException(resp.statusCode, _text(resp));
  }
}

Object? _decode(http.Response resp, {required bool enveloped}) {
  _checkStatus(resp);
  final text = _text(resp);
  if (resp.statusCode == 204 || text.trim().isEmpty) return null;
  final Object? parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException catch (e) {
    throw LowcodbException(
        statusCode: resp.statusCode,
        message: 'lowcodb: invalid JSON response: ${e.message}',
        body: text);
  }
  if (enveloped && parsed is Map && parsed.containsKey('data')) return parsed['data'];
  return parsed;
}

T _one<T>(Object? data, T Function(Map<String, dynamic>) fromJson) =>
    readObject(data, fromJson) ?? fromJson(const {});

List<T> _many<T>(Object? data, T Function(Map<String, dynamic>) fromJson) =>
    readObjectList(data, fromJson) ?? <T>[];

Map<String, dynamic> _record(Object? data) => readMap(data) ?? <String, dynamic>{};

List<Map<String, dynamic>> _records(Object? data) => readMapList(data) ?? [];
