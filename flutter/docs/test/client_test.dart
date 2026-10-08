import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lowcoai_docs/lowcoai_docs.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('config', () {
    test('token is required', () {
      expect(() => DocsClient(token: '', orgId: 'org_1'), throwsArgumentError);
      expect(() => DocsClient(token: '  ', orgId: 'org_1'), throwsArgumentError);
      expect(() => DocsHttpClient(token: '', orgId: 'org_1'), throwsArgumentError);
    });

    test('orgId is required', () {
      expect(
          () => DocsClient(token: 't', orgId: ''),
          throwsA(isA<ArgumentError>()
              .having((e) => e.name, 'name', 'orgId')
              .having((e) => e.message, 'message', contains('X-Org-Id'))));
      expect(() => DocsClient(token: 't', orgId: ' '), throwsArgumentError);
      expect(() => DocsHttpClient(token: 't', orgId: ''), throwsArgumentError);
    });

    test('constants', () {
      expect(lowcoBaseUrl, 'https://api.lowco.ai');
      expect(docsBasePath, '/v1/documents');
      expect(headerOrgId, 'X-Org-Id');
    });
  });

  group('headers', () {
    test('auth, org, accept and extra headers; no content type without a body', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client(headers: {'X-Trace': 't1'}).library.starred('b1');
      final req = rec.last;
      expect(req.url.toString(), 'https://api.lowco.ai/v1/documents/b1/starred');
      expect(req.headers['Authorization'], 'Bearer tok_123');
      expect(req.headers[headerOrgId], 'org_1');
      expect(req.headers['Accept'], 'application/json');
      expect(req.headers['X-Trace'], 't1');
      expect(req.headers.containsKey('Content-Type'), isFalse);
      expect(req.headers.containsKey('X-User-Id'), isFalse);
      expect(req.body, isEmpty);
      expect(req.followRedirects, isTrue);
    });

    test('JSON bodies set the content type, which wins over extra headers', () async {
      final rec = Recorder((_) => envelope({}));
      await rec
          .client(headers: {'Content-Type': 'text/plain'})
          .folders
          .create('b1', const CreateFolderRequest(folderName: 'x'));
      expect(rec.last.headers['Content-Type'], startsWith('application/json'));
      expect(rec.lastJson, {'folderName': 'x'});
    });

    test('an Authorization header in headers takes precedence over the token', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client(headers: {'authorization': 'Basic abc'}).triggers.list();
      expect(rec.last.headers['Authorization'], 'Basic abc');
      expect(rec.last.headers.keys.where((k) => k.toLowerCase() == 'authorization'), hasLength(1));
    });

    test('an X-Org-Id header in headers takes precedence over orgId', () async {
      final rec = Recorder((_) => envelope([]));
      await rec.client(headers: {'x-org-id': 'org_2'}).triggers.list();
      expect(rec.last.headers[headerOrgId], 'org_2');
      expect(rec.last.headers.keys.where((k) => k.toLowerCase() == 'x-org-id'), hasLength(1));
    });

    test('per-request headers and paths on the transport', () async {
      final requests = <http.Request>[];
      final transport = DocsHttpClient(
        token: 'tok',
        orgId: 'org_1',
        headers: {'X-A': 'client'},
        httpClient: MockClient((req) async {
          requests.add(req);
          return envelope({'ok': true});
        }),
      );
      final res = await transport.request('GET', 'v1/documents/custom',
          query: {'a': 1, 'b': null, 'c': false}, headers: {'X-A': 'request'});
      expect(res, {'ok': true});
      expect(
          requests.single.url.toString(), 'https://api.lowco.ai/v1/documents/custom?a=1&c=false');
      expect(requests.single.headers['X-A'], 'request');
      expect(requests.single.headers[headerOrgId], 'org_1');
      expect(requests.single.headers['Authorization'], 'Bearer tok');
    });
  });

  group('responses', () {
    test('unwraps the {status, data} envelope', () async {
      final rec = Recorder((_) => envelope({'id': 'n1', 'name': 'plan.md', 'role': 'viewer'}));
      final node = await rec.client().nodes.get('n1');
      expect(node.id, 'n1');
      expect(node.name, 'plan.md');
      expect(node.role, 'viewer');
    });

    test('payloads without a data key are returned as-is', () async {
      final rec = Recorder((_) => jsonResponse({'id': 't1', 'prefix': 'in/'}, 200));
      expect((await rec.client().triggers.get('t1')).prefix, 'in/');
      final arr = Recorder((_) => jsonResponse([
            {'id': 't1'}
          ], 200));
      expect((await arr.client().triggers.list()).single.id, 't1');
    });

    test('an empty body or null data decodes leniently', () async {
      final client = Recorder((_) => http.Response('', 200)).client();
      expect(await client.triggers.list(), isEmpty);
      expect((await client.triggers.get('t1')).id, isNull);
      expect(await client.files.delete('b1', 'a.md'), '');
      final nulls = Recorder((_) => envelope(null)).client();
      expect(await nulls.webhooks.list(), isEmpty);
      expect((await nulls.buckets.stats('b1')).totalFiles, isNull);
    });

    test('void methods ignore non-JSON success bodies', () async {
      final rec = Recorder((_) => http.Response('deleted', 200));
      await rec.client().webhooks.delete('w1');
      expect(rec.last.method, 'DELETE');
    });

    test('non-JSON success bodies of typed methods throw with the raw text', () async {
      await expectLater(
        Recorder((_) => http.Response('<html>', 200)).client().triggers.get('t1'),
        throwsA(isA<DocsException>()
            .having((e) => e.status, 'status', 200)
            .having((e) => e.message, 'message', startsWith('Invalid JSON response'))
            .having((e) => e.payload, 'payload', '<html>')),
      );
    });
  });

  group('errors', () {
    test('the {status: 0, error} envelope: details win over the code message', () async {
      final body = {
        'status': 0,
        'error': {'message': 'AAS-00106', 'code': 400, 'details': 'bucket name is required'},
      };
      await expectLater(
        Recorder((_) => jsonResponse(body, 400)).client().buckets.stats('b1'),
        throwsA(isA<DocsException>()
            .having((e) => e.status, 'status', 400)
            .having((e) => e.message, 'message', 'bucket name is required')
            .having((e) => e.code, 'code', 'AAS-00106')
            .having((e) => e.payload, 'payload', body)
            .having((e) => e.precondition, 'precondition', isNull)
            .having(
                (e) => e.toString(), 'toString', 'DocsException(400): bucket name is required')),
      );
    });

    test('the {status: 0, error} envelope without details uses error.message', () async {
      final body = {
        'status': 0,
        'error': {'message': 'AAS-00102', 'code': 404},
      };
      await expectLater(
        Recorder((_) => jsonResponse(body, 404)).client().files.get('b1', 'x.md'),
        throwsA(isA<DocsException>()
            .having((e) => e.message, 'message', 'AAS-00102')
            .having((e) => e.code, 'code', 'AAS-00102')),
      );
    });

    test('a plain error.message is the message, with no code', () async {
      final body = {
        'status': 0,
        'error': {'message': 'quota exceeded', 'code': 400, 'details': 'raw driver error'},
      };
      await expectLater(
        Recorder((_) => jsonResponse(body, 400)).client().triggers.list(),
        throwsA(isA<DocsException>()
            .having((e) => e.message, 'message', 'quota exceeded')
            .having((e) => e.code, 'code', isNull)),
      );
      final detailsOnly = {
        'status': 0,
        'error': {'code': 500, 'details': 'storage error'},
      };
      await expectLater(
        Recorder((_) => jsonResponse(detailsOnly, 500)).client().triggers.list(),
        throwsA(isA<DocsException>().having((e) => e.message, 'message', 'storage error')),
      );
    });

    test('the {message} body', () async {
      final body = {'message': "you don't have access to this item"};
      await expectLater(
        Recorder((_) => jsonResponse(body, 403)).client().folders.list('b1'),
        throwsA(isA<DocsException>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.message, 'message', "you don't have access to this item")
            .having((e) => e.code, 'code', isNull)
            .having((e) => e.payload, 'payload', body)),
      );
    });

    test('412 exposes the current state of the file', () async {
      final body = {
        'status': 0,
        'data': {'currentEtag': 'e2', 'updatedAt': '2026-10-01T09:30:00Z', 'updatedBy': 'u-456'},
        'error': {'message': 'the file was changed by someone else', 'code': 412},
      };
      final rec = Recorder((_) => jsonResponse(body, 412));
      await expectLater(
        rec
            .client()
            .files
            .update('b1', const UpdateFileRequest(fileName: 'a.md', content: 'x', ifMatch: 'e1')),
        throwsA(isA<DocsException>()
            .having((e) => e.status, 'status', 412)
            .having((e) => e.message, 'message', 'the file was changed by someone else')
            .having((e) => e.precondition?.currentEtag, 'currentEtag', 'e2')
            .having((e) => e.precondition?.updatedBy, 'updatedBy', 'u-456')),
      );
      expect(rec.lastJson, {'fileName': 'a.md', 'content': 'x', 'ifMatch': 'e1'});
    });

    test('a JSON body without a message falls back to the status', () async {
      await expectLater(
        Recorder((_) => jsonResponse({'status': 0}, 500)).client().triggers.list(),
        throwsA(isA<DocsException>()
            .having((e) => e.message, 'message', 'Request failed with status 500')),
      );
    });

    test('non-2xx with a non-JSON body keeps the raw text', () async {
      await expectLater(
        Recorder((_) => http.Response('upstream down', 502)).client().triggers.list(),
        throwsA(isA<DocsException>()
            .having((e) => e.status, 'status', 502)
            .having((e) => e.message, 'message', 'Request failed with status 502')
            .having((e) => e.payload, 'payload', 'upstream down')),
      );
    });

    test('non-2xx with an empty body has a null payload', () async {
      await expectLater(
        Recorder((_) => http.Response('', 503)).client().webhooks.delete('w1'),
        throwsA(isA<DocsException>()
            .having((e) => e.status, 'status', 503)
            .having((e) => e.payload, 'payload', isNull)),
      );
    });

    test('transport errors become status 0', () async {
      final client = DocsClient(
        token: 't',
        orgId: 'o',
        httpClient: MockClient((_) async => throw http.ClientException('connection refused')),
      );
      await expectLater(
        client.triggers.list(),
        throwsA(isA<DocsException>()
            .having((e) => e.status, 'status', 0)
            .having((e) => e.message, 'message', 'connection refused')
            .having((e) => e.payload, 'payload', isNull)),
      );
    });

    test('timeouts become status 0', () async {
      final client = DocsClient(
        token: 't',
        orgId: 'o',
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(
        client.triggers.list(),
        throwsA(isA<DocsException>()
            .having((e) => e.status, 'status', 0)
            .having((e) => e.message, 'message', contains('timed out'))),
      );
    });

    test('a null timeout disables it', () async {
      final rec = Recorder((_) => envelope([]));
      expect(await rec.client(timeout: null).triggers.list(), isEmpty);
    });
  });

  group('path and query encoding', () {
    test('single-segment params are fully percent-encoded', () async {
      final rec = Recorder((_) => envelope({}));
      final client = rec.client();
      await client.folders.get('my bucket', 'a/b c?d');
      expect(rec.last.url.toString(),
          'https://api.lowco.ai/v1/documents/my%20bucket/folder/a%2Fb%20c%3Fd');
      await client.nodes.get('n/1#x');
      expect(rec.last.url.path, '/v1/documents/nodes/n%2F1%23x');
      await client.folders.listUser('b1', 'u 1/2');
      expect(rec.last.url.path, '/v1/documents/b1/users/u%201%2F2/objects');
    });

    test('wildcard paths keep their separators and lose leading slashes', () async {
      final rec = Recorder((_) => envelope({}));
      final client = rec.client();
      await client.files.get('b1', 'a b/c.txt');
      expect(rec.last.url.toString(), 'https://api.lowco.ai/v1/documents/b1/file/a%20b/c.txt');
      await client.files.get('b1', '/notes/x%y?.md');
      expect(rec.last.url.path, '/v1/documents/b1/file/notes/x%25y%3F.md');
      await client.folders.listAt('b1', '//projects/2026/', sizes: false);
      expect(rec.last.url.toString(),
          'https://api.lowco.ai/v1/documents/b1/objects/projects/2026/?sizes=false');
      await client.appFiles.delete('my app', '.users/ü/a.pdf');
      expect(rec.last.url.path, '/v1/documents/app-files/my%20app/.users/%C3%BC/a.pdf');
    });

    test('"." and ".." segments are rejected before sending', () async {
      final rec = Recorder((_) => envelope({}));
      final client = rec.client();
      final invalid = <Future<Object?> Function()>[
        () => client.files.get('b1', 'a/../secret.md'),
        () => client.files.downloadUrl('b1', './a.pdf'),
        () => client.folders.listAt('b1', 'projects/.'),
        () => client.appFiles.delete('app', '..'),
        () => client.folders.get('b1', '..'),
        () => client.nodes.get('.'),
        () => client.buckets.stats('..'),
        () => client.sharing.resolveLink('.'),
      ];
      for (final call in invalid) {
        await expectLater(
          call(),
          throwsA(isA<DocsException>()
              .having((e) => e.status, 'status', 0)
              .having((e) => e.message, 'message', contains('".." segments'))),
        );
      }
      expect(rec.requests, isEmpty);

      // Dots inside a segment are fine.
      await client.files.get('b1', '.users/u-1/..notes/a..b.md');
      expect(rec.last.url.path, '/v1/documents/b1/file/.users/u-1/..notes/a..b.md');
    });

    test('null query values are omitted, others URL-encoded', () async {
      final rec = Recorder((_) => envelope([]));
      final client = rec.client();
      await client.folders.list('b1');
      expect(rec.last.url.hasQuery, isFalse);
      await client.folders.list('b1', prefix: 'a&b=c d');
      expect(rec.last.url.queryParameters, {'prefix': 'a&b=c d'});
      expect(rec.last.url.query, isNot(contains('&b')));
      await client.automation.jobs('b1', limit: 5);
      expect(rec.last.url.queryParameters, {'limit': '5'});
      await client.sharing.list('b1', path: 'x.pdf');
      expect(rec.last.url.queryParameters, {'path': 'x.pdf'});
    });
  });

  group('redirect URL methods', () {
    test('return the Location without following the redirect', () async {
      final rec = Recorder((_) => redirect('https://cdn.example.com/f.pdf?X-Amz-Signature=a&b=1'));
      final url = await rec.client().files.downloadUrl('b1', 'f.pdf');
      expect(url, 'https://cdn.example.com/f.pdf?X-Amz-Signature=a&b=1');
      expect(rec.last.followRedirects, isFalse);
      expect(rec.last.headers['Authorization'], 'Bearer tok_123');
      expect(rec.last.headers[headerOrgId], 'org_1');
    });

    test('a relative Location is resolved against the request URL', () async {
      final client = DocsClient(
        token: 't',
        orgId: 'o',
        httpClient: MockClient((req) async =>
            http.Response('', 302, headers: {'location': '/cdn/f.pdf'}, request: req)),
      );
      expect(await client.sharing.resolveLink('tok'), 'https://api.lowco.ai/cdn/f.pdf');
    });

    test('a followed redirect (web) throws a clear error', () async {
      await expectLater(
        Recorder((_) => http.Response('%PDF', 200)).client().files.previewUrl('b1', 'a.docx'),
        throwsA(isA<DocsException>()
            .having((e) => e.status, 'status', 200)
            .having((e) => e.message, 'message', contains('redirect'))
            .having((e) => e.message, 'message', contains('web'))),
      );
    });

    test('error statuses throw the extracted message', () async {
      await expectLater(
        Recorder((_) => jsonResponse({'message': 'this link is no longer valid'}, 404))
            .client()
            .sharing
            .resolveLink('tok'),
        throwsA(isA<DocsException>()
            .having((e) => e.status, 'status', 404)
            .having((e) => e.message, 'message', 'this link is no longer valid')),
      );
    });
  });

  group('binary downloads', () {
    test('X-File-Name names the download', () async {
      final rec = Recorder((_) => http.Response.bytes([1, 2, 3], 200,
          headers: {
            'content-type': 'application/pdf',
            'x-file-name': 'q3 report.pdf',
            'content-disposition': 'inline; filename="other.pdf"',
          }));
      final res = await rec.client().nodes.content('n1');
      expect(res.url, isNull);
      expect(res.restoring, isNull);
      expect(res.isRestoring, isFalse);
      expect(res.content!.data, [1, 2, 3]);
      expect(res.content!.contentType, 'application/pdf');
      expect(res.content!.fileName, 'q3 report.pdf');
      expect(rec.last.followRedirects, isFalse);
    });

    test('Content-Disposition is the fallback for the file name', () async {
      final zip = Recorder((_) => http.Response.bytes(utf8.encode('PK'), 200, headers: {
            'content-type': 'application/zip',
            'content-disposition': r'attachment; filename="q\"3.zip"',
          }));
      final res = await zip.client().folders.downloadZip('b1', 'reports/q3');
      expect(res.fileName, 'q"3.zip');
      expect(res.contentType, 'application/zip');
      expect(res.text(), 'PK');
      expect(zip.last.headers['Accept'], '*/*');

      final extended = Recorder((_) => http.Response.bytes([0], 200,
          headers: {
            'content-disposition':
                "attachment; filename=\"a.zip\"; filename*=UTF-8''r%C3%A9sum%C3%A9.zip",
          }));
      final ext = await extended.client().folders.downloadZip('b1', 'x');
      expect(ext.fileName, 'résumé.zip');
      expect(ext.contentType, 'application/octet-stream');

      final bare = Recorder((_) => http.Response.bytes([0], 200,
          headers: {'content-disposition': 'inline; filename=a.txt'}));
      expect((await bare.client().folders.downloadZip('b1', 'x')).fileName, 'a.txt');

      final none = Recorder((_) => http.Response.bytes([0], 200));
      expect((await none.client().folders.downloadZip('b1', 'x')).fileName, isNull);
    });

    test('binary errors still decode the JSON error body', () async {
      await expectLater(
        Recorder((_) => jsonResponse({'message': 'document content not available'}, 404))
            .client()
            .nodes
            .content('n1'),
        throwsA(isA<DocsException>()
            .having((e) => e.status, 'status', 404)
            .having((e) => e.message, 'message', 'document content not available')),
      );
    });
  });

  group('permalinks', () {
    test('307 resolves to the URL', () async {
      final rec = Recorder((_) => redirect('https://cdn.example.com/x?cap=1'));
      final res = await rec.client().nodes.resolve('n1', download: true);
      expect(res.url, 'https://cdn.example.com/x?cap=1');
      expect(res.content, isNull);
      expect(res.restoring, isNull);
      expect(rec.last.url.queryParameters, {'download': '1'});
      expect(rec.last.followRedirects, isFalse);
    });

    test('200 returns the content of a restored archive', () async {
      final rec = Recorder((_) => http.Response.bytes([7], 200,
          headers: {'content-type': 'text/plain', 'x-file-name': 'a.txt'}));
      final res = await rec.client().nodes.resolve('n1');
      expect(rec.last.url.hasQuery, isFalse);
      expect(res.url, isNull);
      expect(res.content!.data, [7]);
      expect(res.content!.fileName, 'a.txt');
    });

    test('202 returns the restoring state with Retry-After', () async {
      final restoring = {
        'status': 'restoring',
        'nodeId': 'n1',
        'name': 'q3.pdf',
        'retryAfterSeconds': 300,
        'message': 'this file was moved to cold storage',
      };
      for (final call in <Future<NodeFileResult> Function(DocsClient)>[
        (c) => c.nodes.resolve('n1'),
        (c) => c.nodes.content('n1'),
      ]) {
        final rec = Recorder((_) => envelope(restoring, 202, {'retry-after': '300'}));
        final res = await call(rec.client());
        expect(res.isRestoring, isTrue);
        expect(res.url, isNull);
        expect(res.content, isNull);
        expect(res.retryAfter, 300);
        expect(res.restoring!.status, 'restoring');
        expect(res.restoring!.nodeId, 'n1');
        expect(res.restoring!.name, 'q3.pdf');
        expect(res.restoring!.retryAfterSeconds, 300);
      }
    });

    test('202 without Retry-After leaves retryAfter null', () async {
      final res = await Recorder((_) => envelope({'status': 'restoring'}, 202))
          .client()
          .nodes
          .content('n1');
      expect(res.isRestoring, isTrue);
      expect(res.retryAfter, isNull);
    });

    test('410 throws', () async {
      await expectLater(
        Recorder((_) => jsonResponse({'message': 'archived'}, 410)).client().nodes.resolve('n1'),
        throwsA(isA<DocsException>().having((e) => e.status, 'status', 410)),
      );
    });
  });

  group('multipart', () {
    test('files.upload sends file, ParentID and onConflict', () async {
      final rec = Recorder((_) => envelope({'id': 'n1', 'name': 'r.pdf'}));
      final doc = await rec.client().files.upload('b1',
          UploadFile(bytes: [37, 80, 68, 70], fileName: 'r.pdf', contentType: 'application/pdf'),
          parentId: 'reports', onConflict: 'rename');
      expect(doc.id, 'n1');
      final parts = parseMultipart(rec.last);
      expect([for (final p in parts) p.name], ['ParentID', 'onConflict', 'file']);
      expect(parts[0].value, 'reports');
      expect(parts[0].filename, isNull);
      expect(parts[0].contentType, isNull);
      expect(parts[1].value, 'rename');
      expect(parts[2].filename, 'r.pdf');
      expect(parts[2].contentType, 'application/pdf');
      expect(parts[2].value, '%PDF');
      expect(rec.last.headers['Accept'], 'application/json');
    });

    test('defaults and escaping of file parts', () async {
      final rec = Recorder((_) => envelope({}));
      await rec
          .client()
          .appFiles
          .upload('app', UploadFile(bytes: utf8.encode('é'), fileName: 'a "b"\n.bin'));
      final part = parseMultipart(rec.last).single;
      expect(part.name, 'file');
      expect(part.filename, 'a %22b%22%0D%0A.bin');
      expect(part.contentType, 'application/octet-stream');
      expect(part.value, 'é');

      await rec.client().appFiles.upload('app', UploadFile.fromString('hi', fileName: 'h.md'));
      expect(parseMultipart(rec.last).single.contentType, 'text/plain; charset=utf-8');
    });

    test('folders.upload repeats files and relativePaths in order', () async {
      final rec = Recorder((_) => envelope({}));
      await rec.client().folders.upload('b1', [
        UploadFile.fromString('1', fileName: 'a.txt'),
        UploadFile.fromString('2', fileName: 'b.txt'),
        UploadFile.fromString('3', fileName: 'c.txt'),
      ], relativePaths: [
        'p/a.txt',
        'p/q/b.txt',
        'p/c.txt'
      ]);
      final parts = parseMultipart(rec.last);
      expect([for (final p in parts.where((p) => p.name == 'relativePaths')) p.value],
          ['p/a.txt', 'p/q/b.txt', 'p/c.txt']);
      expect([for (final p in parts.where((p) => p.name == 'files')) p.filename],
          ['a.txt', 'b.txt', 'c.txt']);
      expect(parts.where((p) => p.name == 'parentID'), isEmpty);
    });
  });

  test('close does not close an injected client', () {
    final tracking = TrackingClient();
    DocsClient(token: 't', orgId: 'o', httpClient: tracking).close();
    expect(tracking.closed, isFalse);
    // An internally created client can be closed repeatedly.
    DocsClient(token: 't', orgId: 'o')
      ..close()
      ..close();
  });
}
