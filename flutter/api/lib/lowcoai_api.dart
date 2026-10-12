/// Official Dart and Flutter client for the Lowco API: PDF, render, OCR,
/// Document AI, QR and barcodes, with jobs, file inputs, webhooks and typed
/// errors.
library;

import 'package:http/http.dart' as http;

import 'src/core.dart';
import 'src/generated.dart';

export 'src/core.dart'
    show Answer, CallOptions, FileInput, LowcoApiError, LowcoJobError, LowcoTimeoutError, RequestOptions, defaultBaseUrl, newIdempotencyKey, sdkVersion;
export 'src/generated.dart';
export 'src/webhooks.dart';

/// The Lowco API client. `apiKey` defaults to LOWCO_API_KEY and `baseUrl` to
/// LOWCO_API_BASE_URL, else https://api.lowco.ai.
///
/// ```dart
/// final lowco = LowcoApi();
/// final answer = await lowco.docai.invoice(DocaiInvoiceParams(file: FileInput.path('invoice.pdf')), const CallOptions(mode: 'async'));
/// final invoice = await lowco.waitForResult(answer);
/// ```
class LowcoApi extends GeneratedClient {
  LowcoApi({String? apiKey, String? baseUrl, http.Client? httpClient, Duration timeout = const Duration(seconds: 60), int maxRetries = 2})
      : this._(Core(apiKey: apiKey, baseUrl: baseUrl, httpClient: httpClient, timeout: timeout, maxRetries: maxRetries));

  LowcoApi._(this._core) : super(_core);

  final Core _core;

  /// The result of an operation's answer: inline data, or the job's result once it finishes (polling with Retry-After).
  Future<T> waitForResult<T>(Answer<T> answer, T Function(Map<String, dynamic>) decode,
      {Duration timeout = const Duration(minutes: 5), Duration maxInterval = const Duration(seconds: 10)}) async {
    if (answer.data != null) return answer.data as T;
    final job = answer.job;
    if (job == null) throw LowcoApiError('The answer carries bytes, not a result', status: answer.status, reason: ErrorReason.invalidParam);
    final done = await _core.waitForJob(job.jobId!, timeout: timeout, maxInterval: maxInterval);
    return decode(done.result!);
  }

  /// Closes the HTTP client.
  void close() => _core.close();
}
