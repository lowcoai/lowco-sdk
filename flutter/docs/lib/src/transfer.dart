// Upload inputs and binary / redirect results. These are SDK types, not wire
// models: they wrap multipart parts, raw response bytes and the three possible
// answers of the permalink endpoints.

import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

/// One file to upload in a multipart request.
class UploadFile {
  /// Creates an upload from raw [bytes].
  ///
  /// [fileName] is the multipart filename the service stores the file under;
  /// [contentType] defaults to `application/octet-stream`.
  const UploadFile({required this.bytes, required this.fileName, this.contentType});

  /// Creates an upload from [text], encoded as UTF-8. [contentType] defaults
  /// to `text/plain; charset=utf-8`.
  factory UploadFile.fromString(String text, {required String fileName, String? contentType}) =>
      UploadFile(
        bytes: utf8.encode(text),
        fileName: fileName,
        contentType: contentType ?? 'text/plain; charset=utf-8',
      );

  /// The file's bytes.
  final List<int> bytes;

  /// The name sent as the multipart `filename`.
  final String fileName;

  /// MIME type of the part; `application/octet-stream` when `null`.
  final String? contentType;
}

/// The bytes of a binary response (a zip, or a file served by node id).
class FileDownload {
  /// Creates a download result.
  const FileDownload({required this.data, required this.contentType, this.fileName});

  /// The response body.
  final Uint8List data;

  /// The response `Content-Type` (`application/octet-stream` when absent).
  final String contentType;

  /// The file name from the `X-File-Name` header, else from the
  /// `Content-Disposition` `filename`; `null` when neither is present.
  final String? fileName;

  /// The body decoded as UTF-8 (malformed sequences are replaced).
  String text() => utf8.decode(data, allowMalformed: true);
}

/// The answer of a permalink endpoint (`nodes.resolve`, `nodes.content`).
///
/// Exactly one of [url], [content] and [restoring] is set:
/// * [url] — the `307` redirect target, a fresh short-lived URL for the file;
/// * [content] — the file's bytes (`200`);
/// * [restoring] — the file is in cold storage and its restore is running
///   (`202`); retry after [retryAfter] seconds.
class NodeFileResult {
  /// Creates a result; set exactly one of [url], [content] and [restoring].
  const NodeFileResult({this.url, this.content, this.restoring, this.retryAfter});

  /// Redirect target (`Location` of the `307`).
  final String? url;

  /// File bytes of a `200`.
  final FileDownload? content;

  /// Body of a `202`: the restore from cold storage is in progress.
  final ArchiveRestoring? restoring;

  /// Seconds to wait before retrying, from the `Retry-After` header of a
  /// `202`; `null` when the header is absent.
  final int? retryAfter;

  /// Whether the file is still being restored from cold storage.
  bool get isRestoring => restoring != null;
}
