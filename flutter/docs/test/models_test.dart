import 'dart:convert';

import 'package:lowcoai_docs/lowcoai_docs.dart';
import 'package:test/test.dart';

const _base = {
  'id': '7489521000000000042',
  'orgId': 'org-1',
  'createdBy': 'u-123',
  'updatedBy': 'u-124',
  'deletedBy': 'u-125',
  'createdAt': '2026-10-01T09:30:00Z',
  'updatedAt': '2026-10-02T11:00:00Z',
  'deletedAt': '2026-10-03T11:00:00Z',
  'prn': 'prn:x',
};

const _document = {
  ..._base,
  'baseUrl': 'https://cdn.example.com/org-bucket/projects/plan.md',
  'category': 'md',
  'content': '# Plan',
  'contentType': 'text/markdown; charset=utf-8',
  'etag': '9b2c',
  'isTrashed': false,
  'metadata': {'role': 'owner', 'sharing': 'none'},
  'name': 'plan.md',
  'parentId': 'projects',
  'path': '/projects/plan.md',
  'publicUrl': 'https://cdn.example.com/org-bucket/projects/plan.md',
  'signedUrl': 'https://s3.example.com/x?sig=1',
  'size': 128,
  'type': 'file',
};

const _nodeView = {
  ..._base,
  'appKey': 'notes',
  'bucket': 'org-bucket',
  'category': 'md',
  'checksum': 'abc',
  'contentType': 'text/markdown',
  'isTrashed': false,
  'key': '.users/u-1/notes/a.md',
  'metadata': {
    'tags': ['a'],
    'n': 1
  },
  'name': 'a.md',
  'ownerId': 'u-1',
  'parentKey': '.users/u-1/notes/',
  'restoreKey': '',
  'role': 'viewer',
  'size': 10,
  'space': 'user',
  'trashedAt': '2026-10-04T00:00:00Z',
  'trashedBy': 'u-1',
  'type': 'file',
  'visibility': 'private',
};

const _folderConfig = {
  ..._base,
  'active': true,
  'bucket': 'org-bucket',
  'config': {
    'lang': 'en',
    'pages': [1, 2]
  },
  'eventTypes': ['create', 'update'],
  'fileSuffixes': ['.pdf'],
  'pipelineType': 'custom_workflow',
  'prefix': 'invoices/',
  'workflowId': 'wf1',
  'workflowName': 'Invoice intake',
};

const _webhook = {
  ..._base,
  'active': true,
  'eventTypes': ['create'],
  'headers': {'X-Secret': 's'},
  'method': 'POST',
  'prefix': 'uploads/',
  'suffix': '.png',
  'url': 'https://hooks.example.com/docs',
};

void main() {
  group('round trips', () {
    final fixtures =
        <String, (Map<String, dynamic>, Map<String, dynamic> Function(Map<String, dynamic>))>{
      'Document': (_document, (j) => Document.fromJson(j).toJson()),
      'NodeView': (_nodeView, (j) => NodeView.fromJson(j).toJson()),
      'FolderConfig': (_folderConfig, (j) => FolderConfig.fromJson(j).toJson()),
      'Webhook': (_webhook, (j) => Webhook.fromJson(j).toJson()),
      'Trigger': (
        {
          ..._base,
          'active': true,
          'eventType': 'create',
          'prefix': 'in/',
          'suffix': '.pdf',
          'workflowId': 'wf1',
          'workflowName': 'W',
        },
        (j) => Trigger.fromJson(j).toJson()
      ),
      'Share': (
        {
          ..._base,
          'bucket': 'b',
          'expiresAt': '2026-12-31T00:00:00Z',
          'nodeId': 'n1',
          'role': 'editor',
          'subjectId': 'u-2',
          'subjectType': 'user',
        },
        (j) => Share.fromJson(j).toJson()
      ),
      'ShareLink': (
        {
          ..._base,
          'active': true,
          'bucket': 'b',
          'expiresAt': '2026-12-31T00:00:00Z',
          'nodeId': 'n1',
          'role': 'viewer',
          'scope': 'org',
          'token': 'tok',
        },
        (j) => ShareLink.fromJson(j).toJson()
      ),
      'ProcessingJob': (
        {
          ..._base,
          'attempts': 2,
          'bucket': 'b',
          'error': 'boom',
          'eventType': 'update',
          'folderConfigId': 'fc1',
          'key': 'invoices/a.pdf',
          'nodeId': 'n1',
          'pipelineType': 'extract_text',
          'result': {'chars': 120},
          'status': 'failed',
        },
        (j) => ProcessingJob.fromJson(j).toJson()
      ),
      'FileContent': (
        {
          'content': '# Todo',
          'contentType': 'text/markdown',
          'etag': 'e1',
          'id': 'n1',
          'name': 'todo.md',
          'ownerId': 'u-1',
          'path': '.users/u-1/notes/todo.md',
          'role': 'owner',
          'size': 6,
          'type': 'file',
          'updatedAt': '2026-10-01T09:30:00Z',
          'updatedBy': 'u-1',
        },
        (j) => FileContent.fromJson(j).toJson()
      ),
      'ArchiveListing': (
        {
          'path': 'exports/report.zip',
          'count': 1,
          'entries': [
            {'name': 'report/summary.pdf', 'size': 20480, 'compressedSize': 18311, 'isDir': false}
          ],
        },
        (j) => ArchiveListing.fromJson(j).toJson()
      ),
      'UploadFolderResult': (
        {
          'folder': {'name': 'photos', 'type': 'folder'},
          'files': [_document],
        },
        (j) => UploadFolderResult.fromJson(j).toJson()
      ),
      'BucketStats': (
        {
          'folderCount': 1,
          'systemFiles': 2,
          'systemSize': 3,
          'totalFiles': 4,
          'totalSize': 5,
          'visibleFiles': 6,
          'visibleSize': 7,
        },
        (j) => BucketStats.fromJson(j).toJson()
      ),
      'AppFileUpload': (
        {
          'appKey': 'invoicing',
          'contentType': 'application/pdf',
          'name': 'INV-0042.pdf',
          'nodeId': 'n1',
          'path': '.apps/invoicing/2026/INV-0042.pdf',
          'permalink': '/v1/documents/d/n1',
          'publicUrl': 'https://cdn.example.com/x',
          'signedUrl': 'https://s3.example.com/x',
          'size': 20480,
        },
        (j) => AppFileUpload.fromJson(j).toJson()
      ),
      'AppFilesSweep': (
        {
          'archived': 2,
          'candidates': 3,
          'failed': 1,
          'olderThan': '720h0m0s',
          'prefix': '.apps/agentx/skills/',
          'reason': '',
          'skipped': false,
        },
        (j) => AppFilesSweep.fromJson(j).toJson()
      ),
      'ArchiveRestoring': (
        {
          'message': 'restoring',
          'name': 'q3.pdf',
          'nodeId': 'n1',
          'retryAfterSeconds': 300,
          'status': 'restoring',
        },
        (j) => ArchiveRestoring.fromJson(j).toJson()
      ),
      'ShareLinkCreated': (
        {
          'expiresAt': '2026-12-31T00:00:00Z',
          'id': 'l1',
          'scope': 'org',
          'token': 'tok',
          'url': '/v1/documents/link/tok',
        },
        (j) => ShareLinkCreated.fromJson(j).toJson()
      ),
      'PreconditionState': (
        {'currentEtag': 'e2', 'updatedAt': '2026-10-01T09:30:00Z', 'updatedBy': 'u-456'},
        (j) => PreconditionState.fromJson(j).toJson()
      ),
      'ErrorBody': (
        {'message': 'AAS-00106', 'code': 400, 'details': 'bucket name is required'},
        (j) => ErrorBody.fromJson(j).toJson()
      ),
    };

    fixtures.forEach((name, fixture) {
      test(name, () {
        final (json, roundTrip) = fixture;
        // Go through a JSON string so the input looks like a real response.
        final decoded = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
        expect(roundTrip(decoded), json);
      });
    });
  });

  test('typed fields of a document', () {
    final doc = Document.fromJson(_document);
    expect(doc, isA<BaseEntity>());
    expect(doc.id, '7489521000000000042');
    expect(doc.createdAt, '2026-10-01T09:30:00Z');
    expect(doc.size, 128);
    expect(doc.isTrashed, isFalse);
    expect(doc.metadata!['role'], 'owner');
    expect(doc.type, 'file');
  });

  test('decoding is lenient', () {
    final doc = Document.fromJson({
      'id': 42,
      'size': '128',
      'isTrashed': 'true',
      'metadata': {'n': 1},
      'type': null,
    });
    expect(doc.id, '42');
    expect(doc.size, 128);
    expect(doc.isTrashed, isTrue);
    expect(doc.metadata, {'n': '1'});
    expect(doc.type, isNull);

    final empty = Document.fromJson(const {});
    expect(empty.toJson(), isEmpty);

    final restoring = ArchiveRestoring.fromJson({'retryAfterSeconds': 300.0});
    expect(restoring.retryAfterSeconds, 300);
  });

  test('envelope', () {
    final env = ApiEnvelope.fromJson({
      'status': 0,
      'data': null,
      'error': {'message': 'AAS-00103', 'code': 401, 'details': 'missing token'},
    });
    expect(env.status, 0);
    expect(env.error!.details, 'missing token');
    expect(env.error!.code, 401);
    expect(env.toJson(), {
      'status': 0,
      'error': {'message': 'AAS-00103', 'code': 401, 'details': 'missing token'},
    });
  });

  group('request bodies', () {
    test('toJson omits unset optional fields and always sends required ones', () {
      expect(const CreateFolderRequest(folderName: 'a').toJson(), {'folderName': 'a'});
      expect(const RenameRequest(oldName: 'a', newName: 'b', parentName: '').toJson(),
          {'oldName': 'a', 'newName': 'b', 'parentName': ''});
      expect(const CreateBlankFileRequest(fileName: 'a.md', parentName: 'n').toJson(),
          {'fileName': 'a.md', 'parentName': 'n'});
      expect(
          const UpdateFileRequest(fileName: 'a.md', content: '', ifNoneMatch: '*', id: '').toJson(),
          {'fileName': 'a.md', 'content': '', 'ifNoneMatch': '*', 'id': ''});
      expect(const DuplicateRequest(path: 'a').toJson(), {'path': 'a'});
      expect(const StarByPathRequest(path: 'a', type: 'folder').toJson(),
          {'path': 'a', 'type': 'folder'});
      expect(const CreateShareRequest(path: 'p', subjectType: 'org', role: 'editor').toJson(),
          {'path': 'p', 'subjectType': 'org', 'role': 'editor'});
      expect(const CreateShareLinkRequest(path: 'p', type: 'file').toJson(),
          {'path': 'p', 'type': 'file'});
      expect(
          const FolderConfigRequest(prefix: 'a/', pipelineType: 'thumbnail', active: false)
              .toJson(),
          {'prefix': 'a/', 'pipelineType': 'thumbnail', 'active': false});
      expect(const SweepRequest().toJson(), isEmpty);
      expect(const TriggerRequest(prefix: 'a/', workflowId: 'w').toJson(),
          {'prefix': 'a/', 'workflowId': 'w'});
      expect(const WebhookRequest(url: 'u', method: 'POST', prefix: 'a/', eventTypes: []).toJson(),
          {'url': 'u', 'method': 'POST', 'prefix': 'a/', 'eventTypes': <String>[]});
    });

    test('fromJson fills required fields with empty defaults', () {
      final req = WebhookRequest.fromJson(const {});
      expect(req.url, '');
      expect(req.eventTypes, isEmpty);
      expect(UpdateFileRequest.fromJson(const {'content': 'x'}).content, 'x');
    });
  });

  test('upload inputs', () {
    final text = UploadFile.fromString('héllo', fileName: 'a.txt');
    expect(text.bytes, utf8.encode('héllo'));
    expect(text.contentType, 'text/plain; charset=utf-8');
    final csv = UploadFile.fromString('a,b', fileName: 'a.csv', contentType: 'text/csv');
    expect(csv.contentType, 'text/csv');
    expect(const UploadFile(bytes: [1], fileName: 'b').contentType, isNull);
  });
}
