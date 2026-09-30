import 'codec.dart';

/// Pagination / sorting / filtering accepted by the workflow list endpoints
/// (the TS SDK's `PaginationQuery`).
///
/// The TS type has an index signature, so any other query parameter goes in
/// [extra]; the typed fields win when a key appears in both.
class PaginationQuery {
  const PaginationQuery({
    this.page,
    this.limit,
    this.sortBy,
    this.sortOrder,
    this.where,
    this.extra = const <String, Object?>{},
  });

  final int? page;
  final int? limit;
  final String? sortBy;

  /// `asc` or `desc`.
  final String? sortOrder;

  /// Filter expression understood by the service.
  final String? where;

  /// Additional query parameters. `null` values are skipped, booleans become
  /// `true`/`false`, numbers and strings their string form, anything else JSON.
  final Map<String, Object?> extra;

  /// The encoded query parameters.
  Map<String, String> toQuery() => encodeQuery({
        ...extra,
        if (page != null) 'page': page,
        if (limit != null) 'limit': limit,
        if (sortBy != null) 'sortBy': sortBy,
        if (sortOrder != null) 'sortOrder': sortOrder,
        if (where != null) 'where': where,
      });
}
