import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lowcoai_api/lowcoai_api.dart';
import 'package:test/test.dart';

final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

class Seen {
  Seen(this.method, this.path, this.query, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, String> query;
  final HttpHeaders headers;
  final List<int> body;
}

List<int> env(Object? data) => utf8.encode(jsonEncode({'status': 1, 'data': data}));

Map<String, dynamic> job(String id, String status, [Map<String, dynamic> extra = const {}]) => {
      'job_id': id, 'service': 'docai', 'operation': 'invoice', 'status': status, 'progress': null, 'input': <String, dynamic>{},
      'result': null, 'error': null, 'usage': null, 'attempts': 1, 'created_at': '2026-10-09T09:30:00Z', 'started_at': null,
      'finished_at': null, 'expires_at': '2026-10-16T09:30:00Z', 'links': {'self': '/v1/jobs/$id', 'cancel': '/v1/jobs/$id/cancel'}, ...extra,
    };

void main() {
  late HttpServer server;
  late String base;
  final seen = <Seen>[];
  var polls = 0;
  var settings = 0;

  Seen last(String path) => seen.lastWhere((s) => s.path == path);

  setUpAll(() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final body = await req.fold<List<int>>([], (a, b) => a..addAll(b));
      seen.add(Seen(req.method, req.uri.path, req.uri.queryParameters, req.headers, body));
      final res = req.response;
      void send(int status, List<int> b, {String type = 'application/json', Map<String, String> headers = const {}}) {
        res.statusCode = status;
        res.headers.set('content-type', type);
        res.headers.set('x-request-id', 'req_test');
        headers.forEach(res.headers.set);
        res.add(b);
        res.close();
      }

      List<int> err(int code, String reason, String message, [String? param]) => utf8.encode(jsonEncode({
            'status': 0,
            'error': {'code': code, 'reason': reason, 'message': message, 'param': param, 'request_id': 'req_err', 'doc_url': 'https://docs.lowco.ai/api/errors#$reason'}
          }));
      if (req.headers.value('authorization') != 'Bearer lc_test_sdk' && !req.uri.path.startsWith('/v1/downloads/')) {
        return send(401, err(401, 'missing_key', 'No key'));
      }
      switch ('${req.method} ${req.uri.path}') {
        case 'POST /v1/qr/generate':
          if (req.headers.value('accept') == 'image/png') return send(200, png, type: 'image/png');
          return send(200, env({'format': 'png', 'width': 512}), headers: {'x-lowco-credits-used': '0.0500'});
        case 'POST /v1/docai/invoice':
          if (req.uri.queryParameters['mode'] == 'async') return send(202, env(job('job_inv', 'queued')), headers: {'retry-after': '0'});
          return send(200, env(<String, dynamic>{}));
        case 'GET /v1/jobs/job_inv':
          polls++;
          if (polls < 3) return send(200, env(job('job_inv', 'processing')), headers: {'retry-after': '0'});
          return send(200, env(job('job_inv', 'succeeded', {
                'result': {
                  'invoice_number': {'value': 'INV-1', 'confidence': 0.98, 'source': {'page': 1}}
                }
              })));
        case 'GET /v1/jobs/job_bad':
          return send(200, env(job('job_bad', 'failed', {
                'error': {'code': 422, 'reason': 'file_corrupt', 'message': 'The file is not a readable PDF.', 'doc_url': 'x'}
              })));
        case 'GET /v1/jobs/job_slow':
          return send(200, env(job('job_slow', 'processing')), headers: {'retry-after': '0'});
        case 'GET /v1/jobs':
          if (req.uri.queryParameters['cursor'] == null) {
            return send(200, env({'items': [job('j1', 'succeeded'), job('j2', 'succeeded')], 'next_cursor': 'c2'}));
          }
          return send(200, env({'items': [job('j3', 'failed')], 'next_cursor': null}));
        case 'POST /v1/files':
          return send(201, env({'file_id': 'file_uploaded'}));
        case 'POST /v1/pdf/merge':
          return send(200, env({'pages': 2, 'files_merged': 2, 'file': {'file_id': 'file_m', 'url': null}}));
        case 'POST /v1/pdf/rotate':
          return send(400, err(400, 'invalid_param', 'angle must be 90, 180 or 270.', 'angle'));
        case 'POST /v1/ocr/text':
          return send(202, env(job('job_ocr', 'queued')), headers: {'idempotent-replayed': 'true'});
        case 'GET /v1/settings':
          settings++;
          if (settings == 1) return send(429, err(429, 'rate_limited', 'Slow down'), headers: {'retry-after': '0'});
          return send(200, env({'environment': 'test'}));
        case 'GET /v1/files/file_x/content':
          res.statusCode = 307;
          res.headers.set('location', '$base/v1/downloads/tok_x');
          return res.close();
        case 'GET /v1/downloads/tok_x':
          return send(200, utf8.encode('%PDF-1.7'), type: 'application/pdf');
      }
      send(404, err(404, 'route_not_found', 'no route'));
    });
  });
  tearDownAll(() => server.close(force: true));

  LowcoApi client() => LowcoApi(apiKey: 'lc_test_sdk', baseUrl: base);

  test('an inline answer carries data, the request id and credits', () async {
    final a = await client().qr.generate(const QrGenerateParams(type: 'upi', pa: 'acme@okhdfcbank', pn: 'Acme', am: '1499.00'));
    expect(a.status, 200);
    expect(a.data!.width, 512);
    expect(a.requestId, 'req_test');
    expect(a.creditsUsed, '0.0500');
    expect(jsonDecode(utf8.decode(last('/v1/qr/generate').body)), {'type': 'upi', 'pa': 'acme@okhdfcbank', 'pn': 'Acme', 'am': '1499.00'});
    expect(last('/v1/qr/generate').headers.value('x-client-user-agent'), startsWith('lowcoai-api-dart/'));
  });

  test('accept returns the output file bytes', () async {
    final a = await client().qr.generate(const QrGenerateParams(content: 'x'), const CallOptions(accept: 'image/png'));
    expect(a.bytes, png);
    expect(a.contentType, 'image/png');
  });

  test('a local file goes as multipart with the options as JSON, then the job is waited for', () async {
    final dir = await Directory.systemTemp.createTemp('lowco');
    final f = File('${dir.path}/invoice.pdf')..writeAsStringSync('%PDF-1.7 test');
    final lowco = client();
    final a = await lowco.docai.invoice(DocaiInvoiceParams(file: FileInput.path(f.path), languages: const ['eng', 'hin']), const CallOptions(mode: 'async'));
    expect(a.status, 202);
    expect(a.job!.jobId, 'job_inv');
    final sent = last('/v1/docai/invoice');
    expect(sent.headers.contentType!.mimeType, 'multipart/form-data');
    final text = utf8.decode(sent.body);
    expect(text, contains('name="file"; filename="invoice.pdf"'));
    expect(text, contains('%PDF-1.7 test'));
    expect(text, contains('name="options"\r\n\r\n{"languages":["eng","hin"]}'));
    expect(sent.query['mode'], 'async');
    final inv = await lowco.waitForResult(a, InvoiceResult.fromJson);
    expect(inv.invoiceNumber!.value, 'INV-1');
    expect(polls, 3);
  });

  test('remote inputs go as JSON references; mixed inputs upload the local ones first', () async {
    await client().pdf.merge(PdfMergeParams(files: [FileInput.id('file_a'), FileInput.url('https://example.com/b.pdf')], bookmarks: true));
    expect(jsonDecode(utf8.decode(last('/v1/pdf/merge').body)), {
      'bookmarks': true,
      'files': [{'file_id': 'file_a'}, {'file_url': 'https://example.com/b.pdf'}]
    });
    await client().pdf.merge(PdfMergeParams(files: [FileInput.id('file_a'), FileInput.bytes([37, 80, 68])]));
    expect(last('/v1/files').headers.contentType!.mimeType, 'multipart/form-data');
    expect(jsonDecode(utf8.decode(last('/v1/pdf/merge').body)), {
      'files': [{'file_id': 'file_a'}, {'file_id': 'file_uploaded'}]
    });
  });

  test('an error envelope becomes a typed LowcoApiError', () async {
    await expectLater(
        client().pdf.rotate(PdfRotateParams(file: FileInput.id('file_a'), angle: 45)),
        throwsA(isA<LowcoApiError>()
            .having((e) => e.status, 'status', 400)
            .having((e) => e.reason, 'reason', ErrorReason.invalidParam)
            .having((e) => e.param, 'param', 'angle')
            .having((e) => e.requestId, 'requestId', 'req_err')
            .having((e) => e.docUrl, 'docUrl', 'https://docs.lowco.ai/api/errors#invalid_param')));
    expect(errorReasons[ErrorReason.invalidParam]!.status, 400);
    expect(errorReasons.length, 56);
  });

  test('Idempotency-Key, 429 retries and pagination', () async {
    final key = newIdempotencyKey();
    final a = await client().ocr.text(OcrTextParams(file: FileInput.id('file_a')), CallOptions(idempotencyKey: key, mode: 'async'));
    expect(last('/v1/ocr/text').headers.value('idempotency-key'), key);
    expect(a.replayed, isTrue);
    expect((await client().settings.get()).environment, 'test');
    expect(settings, 2);
    final ids = await client().jobs.listAll(const JobsListQuery(status: 'succeeded')).map((j) => j.jobId).toList();
    expect(ids, ['j1', 'j2', 'j3']);
    expect(last('/v1/jobs').query['cursor'], 'c2');
  });

  test('a failed job throws LowcoJobError; a slow one times out', () async {
    await expectLater(client().jobs.wait('job_bad'),
        throwsA(isA<LowcoJobError>().having((e) => e.reason, 'reason', 'file_corrupt').having((e) => e.job.status, 'status', 'failed')));
    await expectLater(client().jobs.wait('job_slow', timeout: const Duration(milliseconds: 50)), throwsA(isA<LowcoTimeoutError>()));
  });

  test('contentUrl returns the signed link and download fetches it without the key', () async {
    final lowco = client();
    final link = await lowco.files.contentUrl('file_x');
    expect(link, '$base/v1/downloads/tok_x');
    expect(utf8.decode(await lowco.files.download(link)), '%PDF-1.7');
    expect(last('/v1/downloads/tok_x').headers.value('authorization'), isNull);
  });

  test('webhook signatures: the vectors made by lowco-api core/webhooksig', () {
    final vectors = (jsonDecode(File('../../specs/webhook-signature-vectors.json').readAsStringSync()) as Map)['vectors'] as List;
    expect(vectors, hasLength(8));
    for (final v in vectors.cast<Map<String, dynamic>>()) {
      final now = DateTime.fromMillisecondsSinceEpoch((v['now'] as int) * 1000);
      expect(verifySignature(v['header'] as String, utf8.encode(v['body'] as String), v['secret'] as String, now: now), v['valid'], reason: v['name'] as String);
    }
    final ok = vectors.first as Map<String, dynamic>;
    final event = constructEvent(utf8.encode(ok['body'] as String), ok['header'] as String, ok['secret'] as String,
        now: DateTime.fromMillisecondsSinceEpoch((ok['now'] as int) * 1000));
    expect(event['type'], 'job.succeeded');
  });
}
