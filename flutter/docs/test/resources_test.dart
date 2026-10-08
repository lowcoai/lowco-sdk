import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lowcoai_docs/lowcoai_docs.dart';
import 'package:test/test.dart';

import 'support.dart';

const _noBody = Object();

/// One endpoint expectation: [call] must send [method] to [path] (the encoded
/// URL path) with [query] and a JSON [body] (`_noBody` = no body at all), or
/// the multipart [parts] as `(name, filename, value)`.
class Case {
  const Case(this.name, this.call, this.method, this.path,
      {this.query = const {}, this.body = _noBody, this.parts, this.respond});

  final String name;
  final Future<Object?> Function(DocsClient c) call;
  final String method;
  final String path;
  final Map<String, String> query;
  final Object? body;
  final List<(String, String?, String)>? parts;
  final http.Response Function(http.Request)? respond;
}

const _b = 'org-bucket';
const _bp = '/v1/documents/org-bucket';

http.Response _redirect(http.Request _) => redirect('https://cdn.example.com/x?sig=1');
http.Response _bytes(http.Request _) => http.Response('PK', 200);

final _upload = UploadFile.fromString('hello', fileName: 'a.txt');

final cases = <Case>[
  // --- top level -------------------------------------------------------------
  Case('health', (c) => c.health(), 'GET', '/health',
      respond: (_) => http.Response('Working!', 200)),
  Case('search', (c) => c.search(_b, 'q3 report'), 'GET', '$_bp/search', query: {'q': 'q3 report'}),

  // --- buckets ---------------------------------------------------------------
  Case('buckets.get', (c) => c.buckets.get(), 'GET', '/v1/documents'),
  Case('buckets.stats', (c) => c.buckets.stats(_b), 'GET', '$_bp/stats'),

  // --- folders ---------------------------------------------------------------
  Case('folders.list', (c) => c.folders.list(_b, prefix: 'projects/2026', sizes: false), 'GET',
      '$_bp/objects',
      query: {'prefix': 'projects/2026', 'sizes': 'false'}),
  Case('folders.list (no options)', (c) => c.folders.list(_b), 'GET', '$_bp/objects'),
  Case('folders.listAt', (c) => c.folders.listAt(_b, 'projects/q 3/', sizes: true), 'GET',
      '$_bp/objects/projects/q%203/',
      query: {'sizes': 'true'}),
  Case('folders.listPublic', (c) => c.folders.listPublic(_b, prefix: 'handbook'), 'GET',
      '$_bp/public/objects',
      query: {'prefix': 'handbook'}),
  Case('folders.listUser', (c) => c.folders.listUser(_b, 'u/1', prefix: 'notes', sizes: false),
      'GET', '$_bp/users/u%2F1/objects',
      query: {'prefix': 'notes', 'sizes': 'false'}),
  Case('folders.listApp', (c) => c.folders.listApp(_b, 'invoicing'), 'GET',
      '$_bp/apps/invoicing/objects'),
  Case('folders.get', (c) => c.folders.get(_b, 'a/b'), 'GET', '$_bp/folder/a%2Fb'),
  Case(
      'folders.create',
      (c) => c.folders
          .create(_b, const CreateFolderRequest(folderName: '2026/q4', parentName: 'projects')),
      'POST',
      '$_bp/folder',
      body: {'folderName': '2026/q4', 'parentName': 'projects'}),
  Case('folders.delete', (c) => c.folders.delete(_b, 'old'), 'DELETE', '$_bp/folder/old'),
  Case('folders.deleteByPath', (c) => c.folders.deleteByPath(_b, 'a/b/'), 'DELETE', '$_bp/folder',
      query: {'path': 'a/b/'}),
  Case(
      'folders.upload',
      (c) => c.folders.upload(
          _b,
          [
            UploadFile.fromString('one', fileName: 'a.txt'),
            UploadFile(bytes: utf8.encode('two'), fileName: 'b.bin'),
          ],
          relativePaths: ['photos/a.txt', 'photos/2026/b.bin'],
          parentId: 'projects',
          prefix: 'ignored'),
      'POST',
      '$_bp/upload-folder',
      parts: [
        ('relativePaths', null, 'photos/a.txt'),
        ('relativePaths', null, 'photos/2026/b.bin'),
        ('parentID', null, 'projects'),
        ('prefix', null, 'ignored'),
        ('files', 'a.txt', 'one'),
        ('files', 'b.bin', 'two'),
      ]),
  Case('folders.downloadZip', (c) => c.folders.downloadZip(_b, '/reports/q 3'), 'GET',
      '$_bp/folder-zip/reports/q%203',
      respond: _bytes),
  Case(
      'folders.duplicate',
      (c) => c.folders.duplicate(_b, const DuplicateRequest(path: 'plan.md', type: 'file')),
      'POST',
      '$_bp/duplicate',
      body: {'path': 'plan.md', 'type': 'file'}),
  Case(
      'folders.rename',
      (c) => c.folders.rename(_b, const RenameRequest(oldName: 'a', newName: 'b')),
      'PUT',
      '$_bp/folder/rename',
      body: {'oldName': 'a', 'newName': 'b'}),

  // --- files -----------------------------------------------------------------
  Case('files.get', (c) => c.files.get(_b, 'notes/to do.md'), 'GET', '$_bp/file/notes/to%20do.md'),
  Case('files.read', (c) => c.files.read(_b, '.users/u-1/notes/todo.md', meta: true), 'GET',
      '$_bp/file',
      query: {'path': '.users/u-1/notes/todo.md', 'meta': '1'}),
  Case('files.read (meta false is omitted)', (c) => c.files.read(_b, 'a.md', meta: false), 'GET',
      '$_bp/file',
      query: {'path': 'a.md'}),
  Case(
      'files.createBlank',
      (c) => c.files.createBlank(_b, const CreateBlankFileRequest(fileName: 'todo.md')),
      'POST',
      '$_bp/file',
      body: {'fileName': 'todo.md'}),
  Case(
      'files.update',
      (c) => c.files.update(
          _b,
          const UpdateFileRequest(
              fileName: 'todo.md', content: '# Todo', parentName: 'notes', ifMatch: 'e1')),
      'PUT',
      '$_bp/file',
      body: {'fileName': 'todo.md', 'content': '# Todo', 'parentName': 'notes', 'ifMatch': 'e1'}),
  Case(
      'files.updateAt',
      (c) => c.files
          .updateAt(_b, 'notes/todo.md', const UpdateFileRequest(fileName: 'todo.md', content: '')),
      'PUT',
      '$_bp/file/notes/todo.md',
      body: {'fileName': 'todo.md', 'content': ''}),
  Case(
      'files.rename',
      (c) => c.files.rename(
          _b, const RenameRequest(parentName: 'p', oldName: 'draft.md', newName: 'final.md')),
      'PUT',
      '$_bp/file/rename',
      body: {'parentName': 'p', 'oldName': 'draft.md', 'newName': 'final.md'}),
  Case('files.delete', (c) => c.files.delete(_b, 'a/b#c.md'), 'DELETE', '$_bp/file/a/b%23c.md'),
  Case('files.deleteByPath', (c) => c.files.deleteByPath(_b, 'a/b.md'), 'DELETE', '$_bp/file',
      query: {'path': 'a/b.md'}),
  Case(
      'files.upload',
      (c) => c.files.upload(_b, _upload, parentId: 'projects/2026', onConflict: 'rename'),
      'POST',
      '$_bp/upload-file',
      parts: [
        ('ParentID', null, 'projects/2026'),
        ('onConflict', null, 'rename'),
        ('file', 'a.txt', 'hello'),
      ]),
  Case('files.upload (file only)', (c) => c.files.upload(_b, _upload), 'POST', '$_bp/upload-file',
      parts: [('file', 'a.txt', 'hello')]),
  Case('files.downloadUrl', (c) => c.files.downloadUrl(_b, 'a b/c.pdf'), 'GET',
      '$_bp/download/a%20b/c.pdf',
      respond: _redirect),
  Case('files.previewUrl', (c) => c.files.previewUrl(_b, 'deck.pptx'), 'GET',
      '$_bp/preview/deck.pptx',
      respond: _redirect),
  Case('files.listArchive', (c) => c.files.listArchive(_b, 'exports/report.zip'), 'GET',
      '$_bp/archive/exports/report.zip'),

  // --- nodes -----------------------------------------------------------------
  Case('nodes.get', (c) => c.nodes.get('n1'), 'GET', '/v1/documents/nodes/n1'),
  Case('nodes.resolve', (c) => c.nodes.resolve('n1'), 'GET', '/v1/documents/d/n1',
      respond: _redirect),
  Case('nodes.resolve (download)', (c) => c.nodes.resolve('n1', download: true), 'GET',
      '/v1/documents/d/n1',
      query: {'download': '1'}, respond: _redirect),
  Case('nodes.resolve (download false is omitted)', (c) => c.nodes.resolve('n1', download: false),
      'GET', '/v1/documents/d/n1',
      respond: _redirect),
  Case('nodes.content', (c) => c.nodes.content('n 1'), 'GET', '/v1/documents/d/n%201/content',
      respond: _bytes),

  // --- library ---------------------------------------------------------------
  Case('library.star', (c) => c.library.star(_b, 'n1'), 'POST', '$_bp/nodes/n1/star'),
  Case('library.unstar', (c) => c.library.unstar(_b, 'n1'), 'DELETE', '$_bp/nodes/n1/star'),
  Case('library.starPath', (c) => c.library.starPath(_b, 'projects', type: 'folder'), 'POST',
      '$_bp/star',
      body: {'path': 'projects', 'type': 'folder'}),
  Case('library.starPath (default type)', (c) => c.library.starPath(_b, 'plan.md'), 'POST',
      '$_bp/star',
      body: {'path': 'plan.md'}),
  Case('library.unstarPath', (c) => c.library.unstarPath(_b, 'plan.md'), 'DELETE', '$_bp/star',
      query: {'path': 'plan.md'}),
  Case('library.starred', (c) => c.library.starred(_b), 'GET', '$_bp/starred'),
  Case('library.recent', (c) => c.library.recent(_b, limit: 20), 'GET', '$_bp/recent',
      query: {'limit': '20'}),
  Case('library.recent (no limit)', (c) => c.library.recent(_b), 'GET', '$_bp/recent'),
  Case('library.trash', (c) => c.library.trash(_b), 'GET', '$_bp/trash'),
  Case('library.restore', (c) => c.library.restore(_b, 'n1'), 'POST', '$_bp/trash/n1/restore'),
  Case('library.purge', (c) => c.library.purge(_b, 'n1'), 'DELETE', '$_bp/trash/n1'),

  // --- sharing ---------------------------------------------------------------
  Case(
      'sharing.create',
      (c) => c.sharing.create(
          _b,
          const CreateShareRequest(
              path: '.users/u-1/q3.pdf',
              type: 'file',
              subjectType: 'user',
              subjectId: 'u-2',
              role: 'viewer')),
      'POST',
      '$_bp/shares',
      body: {
        'path': '.users/u-1/q3.pdf',
        'type': 'file',
        'subjectType': 'user',
        'subjectId': 'u-2',
        'role': 'viewer',
      }),
  Case('sharing.list', (c) => c.sharing.list(_b, path: '.users/u-1/r', type: 'folder'), 'GET',
      '$_bp/shares',
      query: {'path': '.users/u-1/r', 'type': 'folder'}),
  Case('sharing.delete', (c) => c.sharing.delete(_b, 's1'), 'DELETE', '$_bp/shares/s1'),
  Case('sharing.sharedWithMe', (c) => c.sharing.sharedWithMe(_b, appKey: 'notes'), 'GET',
      '$_bp/shared-with-me',
      query: {'appKey': 'notes'}),
  Case(
      'sharing.createLink',
      (c) => c.sharing.createLink(
          _b, const CreateShareLinkRequest(path: 'q3.pdf', expiresAt: '2026-12-31T00:00:00Z')),
      'POST',
      '$_bp/share-links',
      body: {'path': 'q3.pdf', 'expiresAt': '2026-12-31T00:00:00Z'}),
  Case('sharing.listLinks', (c) => c.sharing.listLinks(_b, path: 'q3.pdf'), 'GET',
      '$_bp/share-links',
      query: {'path': 'q3.pdf'}),
  Case(
      'sharing.deleteLink', (c) => c.sharing.deleteLink(_b, 'l1'), 'DELETE', '$_bp/share-links/l1'),
  Case('sharing.resolveLink', (c) => c.sharing.resolveLink('tok/en'), 'GET',
      '/v1/documents/link/tok%2Fen',
      respond: _redirect),

  // --- automation ------------------------------------------------------------
  Case('automation.list', (c) => c.automation.list(_b, prefix: 'invoices/'), 'GET',
      '$_bp/folder-configs',
      query: {'prefix': 'invoices/'}),
  Case(
      'automation.create',
      (c) => c.automation.create(
          _b,
          const FolderConfigRequest(
              prefix: 'invoices/',
              pipelineType: 'custom_workflow',
              workflowId: 'wf1',
              fileSuffixes: ['.pdf'],
              eventTypes: ['create'],
              active: true,
              config: {'lang': 'en'})),
      'POST',
      '$_bp/folder-configs',
      body: {
        'prefix': 'invoices/',
        'pipelineType': 'custom_workflow',
        'workflowId': 'wf1',
        'fileSuffixes': ['.pdf'],
        'eventTypes': ['create'],
        'active': true,
        'config': {'lang': 'en'},
      }),
  Case('automation.get', (c) => c.automation.get(_b, 'fc1'), 'GET', '$_bp/folder-configs/fc1'),
  Case(
      'automation.update',
      (c) => c.automation
          .update(_b, 'fc1', const FolderConfigRequest(prefix: 'in/', pipelineType: 'thumbnail')),
      'PUT',
      '$_bp/folder-configs/fc1',
      body: {'prefix': 'in/', 'pipelineType': 'thumbnail'}),
  Case('automation.delete', (c) => c.automation.delete(_b, 'fc1'), 'DELETE',
      '$_bp/folder-configs/fc1'),
  Case('automation.jobs', (c) => c.automation.jobs(_b, configId: 'fc1', limit: 10), 'GET',
      '$_bp/processing-jobs',
      query: {'configId': 'fc1', 'limit': '10'}),

  // --- app files -------------------------------------------------------------
  Case(
      'appFiles.upload',
      (c) => c.appFiles.upload('invoicing', _upload, path: '2026', onConflict: 'replace'),
      'POST',
      '/v1/documents/app-files/invoicing',
      parts: [
        ('path', null, '2026'),
        ('onConflict', null, 'replace'),
        ('file', 'a.txt', 'hello'),
      ]),
  Case('appFiles.list', (c) => c.appFiles.list('invoicing', prefix: '2026'), 'GET',
      '/v1/documents/app-files/invoicing/objects',
      query: {'prefix': '2026'}),
  Case('appFiles.delete', (c) => c.appFiles.delete('invoicing', '2026/INV 1.pdf'), 'DELETE',
      '/v1/documents/app-files/invoicing/2026/INV%201.pdf'),
  Case(
      'appFiles.sweep',
      (c) => c.appFiles
          .sweep('agentx', const SweepRequest(prefix: 'skills', olderThanDays: 30, limit: 100)),
      'POST',
      '/v1/documents/app-files/agentx/sweep',
      body: {'prefix': 'skills', 'olderThanDays': 30, 'limit': 100}),

  // --- triggers --------------------------------------------------------------
  Case('triggers.list', (c) => c.triggers.list(), 'GET', '/v1/documents/triggers'),
  Case(
      'triggers.create',
      (c) => c.triggers.create(const TriggerRequest(
          prefix: 'invoices/', workflowId: 'wf1', eventType: 'create', active: true)),
      'POST',
      '/v1/documents/triggers',
      body: {'prefix': 'invoices/', 'workflowId': 'wf1', 'eventType': 'create', 'active': true}),
  Case('triggers.get', (c) => c.triggers.get('t1'), 'GET', '/v1/documents/triggers/t1'),
  Case(
      'triggers.update',
      (c) => c.triggers
          .update('t1', const TriggerRequest(prefix: 'in/', workflowId: 'wf2', suffix: '.pdf')),
      'PUT',
      '/v1/documents/triggers/t1',
      body: {'prefix': 'in/', 'workflowId': 'wf2', 'suffix': '.pdf'}),
  Case('triggers.delete', (c) => c.triggers.delete('t1'), 'DELETE', '/v1/documents/triggers/t1'),

  // --- webhooks --------------------------------------------------------------
  Case('webhooks.list', (c) => c.webhooks.list(page: 2, limit: 25), 'GET', '/v1/documents/webhooks',
      query: {'page': '2', 'limit': '25'}),
  Case('webhooks.list (no paging)', (c) => c.webhooks.list(), 'GET', '/v1/documents/webhooks'),
  Case(
      'webhooks.create',
      (c) => c.webhooks.create(const WebhookRequest(
          url: 'https://hooks.example.com/docs',
          method: 'POST',
          prefix: 'uploads/',
          eventTypes: ['create', 'update'],
          headers: {'X-Secret': 's'},
          active: true)),
      'POST',
      '/v1/documents/webhooks',
      body: {
        'url': 'https://hooks.example.com/docs',
        'method': 'POST',
        'prefix': 'uploads/',
        'eventTypes': ['create', 'update'],
        'headers': {'X-Secret': 's'},
        'active': true,
      }),
  Case('webhooks.get', (c) => c.webhooks.get('w1'), 'GET', '/v1/documents/webhooks/w1'),
  Case(
      'webhooks.update',
      (c) => c.webhooks.update(
          'w1',
          const WebhookRequest(
              url: 'https://h', method: 'PUT', prefix: 'a/', eventTypes: ['delete'])),
      'PUT',
      '/v1/documents/webhooks/w1',
      body: {
        'url': 'https://h',
        'method': 'PUT',
        'prefix': 'a/',
        'eventTypes': ['delete'],
      }),
  Case('webhooks.delete', (c) => c.webhooks.delete('w1'), 'DELETE', '/v1/documents/webhooks/w1',
      respond: (_) => http.Response('', 204)),
];

void main() {
  group('endpoints', () {
    for (final tc in cases) {
      test(tc.name, () async {
        final rec = Recorder(tc.respond ?? (_) => envelope({}));
        await tc.call(rec.client());
        final req = rec.requests.single;
        expect(req.method, tc.method);
        expect(req.url.host, 'api.lowco.ai');
        expect(req.url.scheme, 'https');
        expect(req.url.path, tc.path);
        expect(req.url.queryParameters, tc.query);
        expect(req.headers['Authorization'], 'Bearer tok_123');
        expect(req.headers['X-Org-Id'], 'org_1');
        final parts = tc.parts;
        if (parts != null) {
          expect(req.headers['Content-Type'], startsWith('multipart/form-data; boundary='));
          expect([for (final p in parseMultipart(req)) (p.name, p.filename, p.value)], parts);
        } else if (identical(tc.body, _noBody)) {
          expect(req.body, isEmpty);
          expect(req.headers.containsKey('Content-Type'), isFalse);
        } else {
          expect(req.headers['Content-Type'], startsWith('application/json'));
          expect(jsonDecode(req.body), tc.body);
        }
      });
    }
  });

  test('every method is exercised', () {
    final covered = cases.map((c) => c.name.split(' ').first).toSet();
    expect(
        covered,
        containsAll(<String>[
          'health',
          'search',
          for (final m in ['get', 'stats']) 'buckets.$m',
          for (final m in [
            'list',
            'listAt',
            'listPublic',
            'listUser',
            'listApp',
            'get',
            'create',
            'delete',
            'deleteByPath',
            'upload',
            'downloadZip',
            'duplicate',
            'rename',
          ])
            'folders.$m',
          for (final m in [
            'get',
            'read',
            'createBlank',
            'update',
            'updateAt',
            'rename',
            'delete',
            'deleteByPath',
            'upload',
            'downloadUrl',
            'previewUrl',
            'listArchive',
          ])
            'files.$m',
          for (final m in ['get', 'resolve', 'content']) 'nodes.$m',
          for (final m in [
            'star',
            'unstar',
            'starPath',
            'unstarPath',
            'starred',
            'recent',
            'trash',
            'restore',
            'purge',
          ])
            'library.$m',
          for (final m in [
            'create',
            'list',
            'delete',
            'sharedWithMe',
            'createLink',
            'listLinks',
            'deleteLink',
            'resolveLink',
          ])
            'sharing.$m',
          for (final m in ['list', 'create', 'get', 'update', 'delete', 'jobs']) 'automation.$m',
          for (final m in ['upload', 'list', 'delete', 'sweep']) 'appFiles.$m',
          for (final m in ['list', 'create', 'get', 'update', 'delete']) 'triggers.$m',
          for (final m in ['list', 'create', 'get', 'update', 'delete']) 'webhooks.$m',
        ]));
    expect(covered, hasLength(69));
  });

  group('typed results', () {
    test('health returns the plain-text body', () async {
      final rec = Recorder((_) => http.Response('Working!', 200));
      expect(await rec.client().health(), 'Working!');
      expect(rec.last.url.toString(), 'https://api.lowco.ai/health');
    });

    test('lists of documents', () async {
      final rec = Recorder((_) => envelope([
            {
              'id': 'n1',
              'name': 'plan.md',
              'path': 'projects/plan.md',
              'type': 'file',
              'size': 128,
              'metadata': {'role': 'owner', 'etag': 'e1'},
            },
            {'id': 'n2', 'name': 'projects', 'type': 'folder'},
          ]));
      final docs = await rec.client().folders.list(_b);
      expect(docs, hasLength(2));
      expect(docs.first.size, 128);
      expect(docs.first.metadata, {'role': 'owner', 'etag': 'e1'});
      expect(docs.last.type, 'folder');
    });

    test('message responses return the confirmation', () async {
      final rec = Recorder((_) => envelope('file deleted'));
      expect(await rec.client().files.delete(_b, 'a.md'), 'file deleted');
    });

    test('bucket, stats, upload results and app files', () async {
      final client = Recorder((req) {
        if (req.url.path.endsWith('/stats')) {
          return envelope({'totalFiles': 3, 'totalSize': 300, 'folderCount': 1});
        }
        if (req.url.path.endsWith('/upload-folder')) {
          return envelope({
            'folder': {'name': 'photos', 'type': 'folder'},
            'files': [
              {'name': 'a.jpg', 'type': 'file'}
            ],
          });
        }
        if (req.url.path.contains('/app-files/')) {
          return envelope({
            'appKey': 'invoicing',
            'name': 'a.txt',
            'nodeId': 'n9',
            'permalink': '/v1/documents/d/n9',
            'size': 5,
          });
        }
        return envelope({
          'name': 'org-bucket',
          'type': 'folder',
          'size': 1024,
          'metadata': {'privateNotes': 'false'},
        });
      }).client();

      final bucket = await client.buckets.get();
      expect(bucket.name, 'org-bucket');
      expect(bucket.metadata!['privateNotes'], 'false');

      final stats = await client.buckets.stats(_b);
      expect(stats.totalFiles, 3);
      expect(stats.totalSize, 300);

      final up = await client.folders.upload(_b, [_upload]);
      expect(up.folder!.name, 'photos');
      expect(up.files!.single.name, 'a.jpg');

      final app = await client.appFiles.upload('invoicing', _upload);
      expect(app.permalink, '/v1/documents/d/n9');
      expect(app.nodeId, 'n9');
    });

    test('share links, automation and jobs', () async {
      final link = await Recorder((_) => envelope({
            'id': 'l1',
            'token': 'tok',
            'url': '/v1/documents/link/tok',
            'scope': 'org',
            'expiresAt': null,
          })).client().sharing.createLink(_b, const CreateShareLinkRequest(path: 'q3.pdf'));
      expect(link.url, '/v1/documents/link/tok');
      expect(link.expiresAt, isNull);

      final jobs = await Recorder((_) => envelope([
            {
              'id': 'j1',
              'status': 'succeeded',
              'attempts': 1,
              'result': {'pages': 3},
              'eventType': 'create',
            }
          ])).client().automation.jobs(_b);
      expect(jobs.single.status, 'succeeded');
      expect(jobs.single.result, {'pages': 3});
    });

    test('triggers.delete accepts a null data envelope', () async {
      final rec = Recorder((_) => envelope(null));
      await rec.client().triggers.delete('t1');
      expect(rec.last.method, 'DELETE');
    });
  });

  test('folders.upload validates its input', () async {
    final client = Recorder().client();
    await expectLater(client.folders.upload(_b, const []), throwsArgumentError);
    await expectLater(
        client.folders.upload(_b, [_upload], relativePaths: ['a', 'b']), throwsArgumentError);
  });
}
