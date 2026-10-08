import 'package:lowcoai_docs/lowcoai_docs.dart';

Future<void> main() async {
  final client = DocsClient(token: '<token-or-api-key>', orgId: 'org_123');
  try {
    // The org's bucket: its name is the bucketName of every other call.
    final bucket = (await client.buckets.get()).name!;

    // Upload a file into a folder, then list the folder.
    await client.folders.create(bucket, const CreateFolderRequest(folderName: 'reports/2026'));
    final uploaded = await client.files.upload(
      bucket,
      UploadFile.fromString('# Q3\n', fileName: 'q3.md', contentType: 'text/markdown'),
      parentId: 'reports/2026',
    );
    print('uploaded ${uploaded.path} (node ${uploaded.id})');

    final rows = await client.folders.list(bucket, prefix: 'reports/2026', sizes: false);
    for (final doc in rows) {
      print('${doc.type} ${doc.name} ${doc.size ?? 0} bytes');
    }

    // Read with the etag, then save conditionally.
    final file = await client.files.read(bucket, 'reports/2026/q3.md');
    await client.files.update(
      bucket,
      UpdateFileRequest(
        parentName: 'reports/2026',
        fileName: 'q3.md',
        content: '${file.content ?? ''}\nRevenue up.\n',
        ifMatch: file.etag,
      ),
    );

    // A short-lived download URL (redirect not followed; not available on the web).
    print('download: ${await client.files.downloadUrl(bucket, 'reports/2026/q3.md')}');

    // Run a workflow whenever a PDF lands in invoices/.
    await client.triggers.create(const TriggerRequest(
      prefix: 'invoices/',
      suffix: '.pdf',
      eventType: 'create',
      workflowId: 'wf_123',
      active: true,
    ));
  } on DocsException catch (e) {
    print('docs error ${e.status} ${e.code ?? ''}: ${e.message}');
  } finally {
    client.close();
  }
}
