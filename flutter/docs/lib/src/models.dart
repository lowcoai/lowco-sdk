// Wire models of the lowco document service (`/v1/documents`), generated from
// the service's OpenAPI spec (`swagger.json` definitions) and reviewed by hand.
// Field names match the JSON the service sends and accepts; `toJson` omits null
// fields so partial payloads only send what you set. Request fields the service
// rejects when missing are `required`. Timestamps are ISO-8601 strings and
// free-form JSON objects are `Map<String, dynamic>`.

import 'json.dart';

/// A JSON object.
typedef JsonObject = Map<String, dynamic>;

/// The `{ status, data, error }` envelope every JSON endpoint answers with
/// (`status` is `1` on success, `0` on failure). The client unwraps `data` for
/// you; this type is only for callers that use `DocsHttpClient` with their
/// own decoding.
class ApiEnvelope {
  const ApiEnvelope({this.status, this.data, this.error});

  factory ApiEnvelope.fromJson(Map<String, dynamic> json) => ApiEnvelope(
        status: readInt(json['status']),
        data: json['data'],
        error: readObject(json['error'], ErrorBody.fromJson),
      );

  /// `1` on success, `0` on failure.
  final int? status;

  /// The payload of a successful response.
  final Object? data;

  /// The error of a failed response.
  final ErrorBody? error;

  Map<String, dynamic> toJson() => {
        if (status != null) 'status': status,
        if (data != null) 'data': data,
        if (error != null) 'error': error!.toJson(),
      };
}

/// Metadata fields shared by every stored entity (`BaseEntity` on the server).
abstract class BaseEntity {
  const BaseEntity({
    this.id,
    this.orgId,
    this.createdBy,
    this.updatedBy,
    this.deletedBy,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.prn,
  });

  /// Entity id.
  final String? id;

  /// Organization the entity belongs to.
  final String? orgId;

  /// User who created the entity.
  final String? createdBy;

  /// User who last updated the entity.
  final String? updatedBy;

  /// User who deleted the entity.
  final String? deletedBy;

  /// ISO-8601 creation timestamp.
  final String? createdAt;

  /// ISO-8601 timestamp of the last update.
  final String? updatedAt;

  /// ISO-8601 deletion timestamp.
  final String? deletedAt;

  /// Platform resource name.
  final String? prn;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (orgId != null) 'orgId': orgId,
        if (createdBy != null) 'createdBy': createdBy,
        if (updatedBy != null) 'updatedBy': updatedBy,
        if (deletedBy != null) 'deletedBy': deletedBy,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (deletedAt != null) 'deletedAt': deletedAt,
        if (prn != null) 'prn': prn,
      };
}

/// A file or folder as listed and returned by most document endpoints (`model.Document`).
class Document extends BaseEntity {
  const Document({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.deletedBy,
    super.createdAt,
    super.updatedAt,
    super.deletedAt,
    super.prn,
    this.baseUrl,
    this.category,
    this.content,
    this.contentType,
    this.etag,
    this.isTrashed,
    this.metadata,
    this.name,
    this.parentId,
    this.path,
    this.publicUrl,
    this.signedUrl,
    this.size,
    this.type,
  });

  factory Document.fromJson(Map<String, dynamic> json) => Document(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        deletedBy: readString(json['deletedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        deletedAt: readString(json['deletedAt']),
        prn: readString(json['prn']),
        baseUrl: readString(json['baseUrl']),
        category: readString(json['category']),
        content: readString(json['content']),
        contentType: readString(json['contentType']),
        etag: readString(json['etag']),
        isTrashed: readBool(json['isTrashed']),
        metadata: readStringMap(json['metadata']),
        name: readString(json['name']),
        parentId: readString(json['parentId']),
        path: readString(json['path']),
        publicUrl: readString(json['publicUrl']),
        signedUrl: readString(json['signedUrl']),
        size: readInt(json['size']),
        type: readString(json['type']),
      );

  /// Public base URL of the object.
  final String? baseUrl;

  /// File category, usually the extension (e.g. `md`).
  final String? category;

  /// Content is the file body, set only by reads and saves of one file.
  final String? content;

  /// MIME type of the file.
  final String? contentType;

  /// ETag is the stored object's entity tag, unquoted — set by saves so a client can make its next
  /// save conditional.
  final String? etag;

  /// Whether the item is in the trash.
  final bool? isTrashed;

  /// Metadata carries per-view extras, e.g. role, etag, sharing, thumbnailUrl.
  final Map<String, String>? metadata;

  /// File or folder name.
  final String? name;

  /// Path of the folder holding the item.
  final String? parentId;

  /// Full key of the item inside the bucket.
  final String? path;

  /// CDN URL of the object.
  final String? publicUrl;

  /// SignedURL is a short-lived presigned URL for direct object access. Present only when
  /// presigning is enabled (rustfs.presign_enabled).
  final String? signedUrl;

  /// Size in bytes (folders: recursive size, `0` when listed with `sizes: false`).
  final int? size;

  /// One of `file`, `folder`.
  final String? type;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (baseUrl != null) 'baseUrl': baseUrl,
        if (category != null) 'category': category,
        if (content != null) 'content': content,
        if (contentType != null) 'contentType': contentType,
        if (etag != null) 'etag': etag,
        if (isTrashed != null) 'isTrashed': isTrashed,
        if (metadata != null) 'metadata': metadata,
        if (name != null) 'name': name,
        if (parentId != null) 'parentId': parentId,
        if (path != null) 'path': path,
        if (publicUrl != null) 'publicUrl': publicUrl,
        if (signedUrl != null) 'signedUrl': signedUrl,
        if (size != null) 'size': size,
        if (type != null) 'type': type,
      };
}

/// A node's stored metadata plus the caller's [role] (`api.NodeView`), as returned by
/// `nodes.get`.
class NodeView extends BaseEntity {
  const NodeView({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.deletedBy,
    super.createdAt,
    super.updatedAt,
    super.deletedAt,
    super.prn,
    this.appKey,
    this.bucket,
    this.category,
    this.checksum,
    this.contentType,
    this.isTrashed,
    this.key,
    this.metadata,
    this.name,
    this.ownerId,
    this.parentKey,
    this.restoreKey,
    this.role,
    this.size,
    this.space,
    this.trashedAt,
    this.trashedBy,
    this.type,
    this.visibility,
  });

  factory NodeView.fromJson(Map<String, dynamic> json) => NodeView(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        deletedBy: readString(json['deletedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        deletedAt: readString(json['deletedAt']),
        prn: readString(json['prn']),
        appKey: readString(json['appKey']),
        bucket: readString(json['bucket']),
        category: readString(json['category']),
        checksum: readString(json['checksum']),
        contentType: readString(json['contentType']),
        isTrashed: readBool(json['isTrashed']),
        key: readString(json['key']),
        metadata: readMap(json['metadata']),
        name: readString(json['name']),
        ownerId: readString(json['ownerId']),
        parentKey: readString(json['parentKey']),
        restoreKey: readString(json['restoreKey']),
        role: readString(json['role']),
        size: readInt(json['size']),
        space: readString(json['space']),
        trashedAt: readString(json['trashedAt']),
        trashedBy: readString(json['trashedBy']),
        type: readString(json['type']),
        visibility: readString(json['visibility']),
      );

  /// App owning the node (app space only).
  final String? appKey;

  /// Bucket holding the node.
  final String? bucket;

  /// File category, usually the extension.
  final String? category;

  /// Content checksum.
  final String? checksum;

  /// MIME type of the file.
  final String? contentType;

  /// Whether the node is in the trash.
  final bool? isTrashed;

  /// Full key of the node inside the bucket.
  final String? key;

  /// Free-form node metadata.
  final Map<String, dynamic>? metadata;

  /// File or folder name.
  final String? name;

  /// Owner of the personal space the key lives in (empty outside `.users/`).
  final String? ownerId;

  /// Key of the parent folder.
  final String? parentKey;

  /// Key the node returns to when restored from the trash.
  final String? restoreKey;

  /// Role is the caller's role on the node. One of `owner`, `editor`, `viewer`.
  final String? role;

  /// Size in bytes.
  final int? size;

  /// One of `org`, `user`, `app`, `system`.
  final String? space;

  /// ISO-8601 time the node was trashed.
  final String? trashedAt;

  /// User who trashed the node.
  final String? trashedBy;

  /// One of `file`, `folder`.
  final String? type;

  /// One of `private`, `org`, `custom`.
  final String? visibility;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (appKey != null) 'appKey': appKey,
        if (bucket != null) 'bucket': bucket,
        if (category != null) 'category': category,
        if (checksum != null) 'checksum': checksum,
        if (contentType != null) 'contentType': contentType,
        if (isTrashed != null) 'isTrashed': isTrashed,
        if (key != null) 'key': key,
        if (metadata != null) 'metadata': metadata,
        if (name != null) 'name': name,
        if (ownerId != null) 'ownerId': ownerId,
        if (parentKey != null) 'parentKey': parentKey,
        if (restoreKey != null) 'restoreKey': restoreKey,
        if (role != null) 'role': role,
        if (size != null) 'size': size,
        if (space != null) 'space': space,
        if (trashedAt != null) 'trashedAt': trashedAt,
        if (trashedBy != null) 'trashedBy': trashedBy,
        if (type != null) 'type': type,
        if (visibility != null) 'visibility': visibility,
      };
}

/// A file read by path: the body (absent with `meta`) plus what a careful editor needs for a
/// conditional save (`api.FileContent`).
class FileContent {
  const FileContent({
    this.content,
    this.contentType,
    this.etag,
    this.id,
    this.name,
    this.ownerId,
    this.path,
    this.role,
    this.size,
    this.type,
    this.updatedAt,
    this.updatedBy,
  });

  factory FileContent.fromJson(Map<String, dynamic> json) => FileContent(
        content: readString(json['content']),
        contentType: readString(json['contentType']),
        etag: readString(json['etag']),
        id: readString(json['id']),
        name: readString(json['name']),
        ownerId: readString(json['ownerId']),
        path: readString(json['path']),
        role: readString(json['role']),
        size: readInt(json['size']),
        type: readString(json['type']),
        updatedAt: readString(json['updatedAt']),
        updatedBy: readString(json['updatedBy']),
      );

  /// Content is the file body; absent when meta=1.
  final String? content;

  final String? contentType;

  /// ETag is the etag of exactly the version read; send it back as ifMatch.
  final String? etag;

  /// Entity id.
  final String? id;

  final String? name;

  /// OwnerID is the owner of the personal space holding the file ("" outside .users/).
  final String? ownerId;

  final String? path;

  /// Role is the caller's role on the file. One of `owner`, `editor`, `viewer`.
  final String? role;

  final int? size;

  /// One of `file`.
  final String? type;

  /// ISO-8601 timestamp of the last update.
  final String? updatedAt;

  /// User who last updated the entity.
  final String? updatedBy;

  Map<String, dynamic> toJson() => {
        if (content != null) 'content': content,
        if (contentType != null) 'contentType': contentType,
        if (etag != null) 'etag': etag,
        if (id != null) 'id': id,
        if (name != null) 'name': name,
        if (ownerId != null) 'ownerId': ownerId,
        if (path != null) 'path': path,
        if (role != null) 'role': role,
        if (size != null) 'size': size,
        if (type != null) 'type': type,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (updatedBy != null) 'updatedBy': updatedBy,
      };
}

/// Storage usage of a bucket, split between visible and hidden system content
/// (`service.BucketStats`).
class BucketStats {
  const BucketStats({
    this.folderCount,
    this.systemFiles,
    this.systemSize,
    this.totalFiles,
    this.totalSize,
    this.visibleFiles,
    this.visibleSize,
  });

  factory BucketStats.fromJson(Map<String, dynamic> json) => BucketStats(
        folderCount: readInt(json['folderCount']),
        systemFiles: readInt(json['systemFiles']),
        systemSize: readInt(json['systemSize']),
        totalFiles: readInt(json['totalFiles']),
        totalSize: readInt(json['totalSize']),
        visibleFiles: readInt(json['visibleFiles']),
        visibleSize: readInt(json['visibleSize']),
      );

  final int? folderCount;

  final int? systemFiles;

  final int? systemSize;

  final int? totalFiles;

  final int? totalSize;

  final int? visibleFiles;

  final int? visibleSize;

  Map<String, dynamic> toJson() => {
        if (folderCount != null) 'folderCount': folderCount,
        if (systemFiles != null) 'systemFiles': systemFiles,
        if (systemSize != null) 'systemSize': systemSize,
        if (totalFiles != null) 'totalFiles': totalFiles,
        if (totalSize != null) 'totalSize': totalSize,
        if (visibleFiles != null) 'visibleFiles': visibleFiles,
        if (visibleSize != null) 'visibleSize': visibleSize,
      };
}

/// One row of a zip listing (`api.ArchiveEntry`).
class ArchiveEntry {
  const ArchiveEntry({
    this.compressedSize,
    this.isDir,
    this.name,
    this.size,
  });

  factory ArchiveEntry.fromJson(Map<String, dynamic> json) => ArchiveEntry(
        compressedSize: readInt(json['compressedSize']),
        isDir: readBool(json['isDir']),
        name: readString(json['name']),
        size: readInt(json['size']),
      );

  final int? compressedSize;

  final bool? isDir;

  final String? name;

  final int? size;

  Map<String, dynamic> toJson() => {
        if (compressedSize != null) 'compressedSize': compressedSize,
        if (isDir != null) 'isDir': isDir,
        if (name != null) 'name': name,
        if (size != null) 'size': size,
      };
}

/// The entries of a stored zip file (`api.ArchiveListing`).
class ArchiveListing {
  const ArchiveListing({
    this.count,
    this.entries,
    this.path,
  });

  factory ArchiveListing.fromJson(Map<String, dynamic> json) => ArchiveListing(
        count: readInt(json['count']),
        entries: readObjectList(json['entries'], ArchiveEntry.fromJson),
        path: readString(json['path']),
      );

  final int? count;

  final List<ArchiveEntry>? entries;

  final String? path;

  Map<String, dynamic> toJson() => {
        if (count != null) 'count': count,
        if (entries != null) 'entries': entries!.map((e) => e.toJson()).toList(),
        if (path != null) 'path': path,
      };
}

/// Body of a `202` answer for a file in cold storage whose restore was requested
/// (`api.ArchiveRestoring`). Retry after [retryAfterSeconds].
class ArchiveRestoring {
  const ArchiveRestoring({
    this.message,
    this.name,
    this.nodeId,
    this.retryAfterSeconds,
    this.status,
  });

  factory ArchiveRestoring.fromJson(Map<String, dynamic> json) => ArchiveRestoring(
        message: readString(json['message']),
        name: readString(json['name']),
        nodeId: readString(json['nodeId']),
        retryAfterSeconds: readInt(json['retryAfterSeconds']),
        status: readString(json['status']),
      );

  final String? message;

  final String? name;

  final String? nodeId;

  final int? retryAfterSeconds;

  /// One of `restoring`.
  final String? status;

  Map<String, dynamic> toJson() => {
        if (message != null) 'message': message,
        if (name != null) 'name': name,
        if (nodeId != null) 'nodeId': nodeId,
        if (retryAfterSeconds != null) 'retryAfterSeconds': retryAfterSeconds,
        if (status != null) 'status': status,
      };
}

/// Result of a folder upload: the folder and the files written (`api.UploadFolderResult`). Files
/// that failed to upload are missing from [files].
class UploadFolderResult {
  const UploadFolderResult({
    this.files,
    this.folder,
  });

  factory UploadFolderResult.fromJson(Map<String, dynamic> json) => UploadFolderResult(
        files: readObjectList(json['files'], Document.fromJson),
        folder: readObject(json['folder'], Document.fromJson),
      );

  final List<Document>? files;

  final Document? folder;

  Map<String, dynamic> toJson() => {
        if (files != null) 'files': files!.map((e) => e.toJson()).toList(),
        if (folder != null) 'folder': folder!.toJson(),
      };
}

/// A grant giving a member (or the whole org) access to a My Drive item (`model.Share`).
class Share extends BaseEntity {
  const Share({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.deletedBy,
    super.createdAt,
    super.updatedAt,
    super.deletedAt,
    super.prn,
    this.bucket,
    this.expiresAt,
    this.nodeId,
    this.role,
    this.subjectId,
    this.subjectType,
  });

  factory Share.fromJson(Map<String, dynamic> json) => Share(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        deletedBy: readString(json['deletedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        deletedAt: readString(json['deletedAt']),
        prn: readString(json['prn']),
        bucket: readString(json['bucket']),
        expiresAt: readString(json['expiresAt']),
        nodeId: readString(json['nodeId']),
        role: readString(json['role']),
        subjectId: readString(json['subjectId']),
        subjectType: readString(json['subjectType']),
      );

  final String? bucket;

  final String? expiresAt;

  final String? nodeId;

  /// One of `viewer`, `editor`.
  final String? role;

  final String? subjectId;

  /// One of `user`, `org`.
  final String? subjectType;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (bucket != null) 'bucket': bucket,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (nodeId != null) 'nodeId': nodeId,
        if (role != null) 'role': role,
        if (subjectId != null) 'subjectId': subjectId,
        if (subjectType != null) 'subjectType': subjectType,
      };
}

/// An org-scope share link of a My Drive file (`model.ShareLink`).
class ShareLink extends BaseEntity {
  const ShareLink({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.deletedBy,
    super.createdAt,
    super.updatedAt,
    super.deletedAt,
    super.prn,
    this.active,
    this.bucket,
    this.expiresAt,
    this.nodeId,
    this.role,
    this.scope,
    this.token,
  });

  factory ShareLink.fromJson(Map<String, dynamic> json) => ShareLink(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        deletedBy: readString(json['deletedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        deletedAt: readString(json['deletedAt']),
        prn: readString(json['prn']),
        active: readBool(json['active']),
        bucket: readString(json['bucket']),
        expiresAt: readString(json['expiresAt']),
        nodeId: readString(json['nodeId']),
        role: readString(json['role']),
        scope: readString(json['scope']),
        token: readString(json['token']),
      );

  final bool? active;

  final String? bucket;

  final String? expiresAt;

  final String? nodeId;

  /// One of `viewer`, `editor`.
  final String? role;

  final String? scope;

  final String? token;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (active != null) 'active': active,
        if (bucket != null) 'bucket': bucket,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (nodeId != null) 'nodeId': nodeId,
        if (role != null) 'role': role,
        if (scope != null) 'scope': scope,
        if (token != null) 'token': token,
      };
}

/// A newly minted share link (`api.ShareLinkCreated`).
class ShareLinkCreated {
  const ShareLinkCreated({
    this.expiresAt,
    this.id,
    this.scope,
    this.token,
    this.url,
  });

  factory ShareLinkCreated.fromJson(Map<String, dynamic> json) => ShareLinkCreated(
        expiresAt: readString(json['expiresAt']),
        id: readString(json['id']),
        scope: readString(json['scope']),
        token: readString(json['token']),
        url: readString(json['url']),
      );

  final String? expiresAt;

  /// Entity id.
  final String? id;

  /// One of `org`.
  final String? scope;

  final String? token;

  /// URL is the API path that resolves the link (GET, redirects to the file).
  final String? url;

  Map<String, dynamic> toJson() => {
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (id != null) 'id': id,
        if (scope != null) 'scope': scope,
        if (token != null) 'token': token,
        if (url != null) 'url': url,
      };
}

/// An automation rule attached to a folder (`model.FolderConfig`).
class FolderConfig extends BaseEntity {
  const FolderConfig({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.deletedBy,
    super.createdAt,
    super.updatedAt,
    super.deletedAt,
    super.prn,
    this.active,
    this.bucket,
    this.config,
    this.eventTypes,
    this.fileSuffixes,
    this.pipelineType,
    this.prefix,
    this.workflowId,
    this.workflowName,
  });

  factory FolderConfig.fromJson(Map<String, dynamic> json) => FolderConfig(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        deletedBy: readString(json['deletedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        deletedAt: readString(json['deletedAt']),
        prn: readString(json['prn']),
        active: readBool(json['active']),
        bucket: readString(json['bucket']),
        config: readMap(json['config']),
        eventTypes: readStringList(json['eventTypes']),
        fileSuffixes: readStringList(json['fileSuffixes']),
        pipelineType: readString(json['pipelineType']),
        prefix: readString(json['prefix']),
        workflowId: readString(json['workflowId']),
        workflowName: readString(json['workflowName']),
      );

  final bool? active;

  final String? bucket;

  final Map<String, dynamic>? config;

  /// EventTypes filters which events fire (create/update); empty = create only. One of `create`,
  /// `update`.
  final List<String>? eventTypes;

  /// FileSuffixes filters which files run (e.g. [".pdf", ".docx"]); empty = all.
  final List<String>? fileSuffixes;

  /// One of `custom_workflow`, `extract_text`, `thumbnail`.
  final String? pipelineType;

  /// Prefix is the folder key the rule is attached to (trailing slash).
  final String? prefix;

  final String? workflowId;

  final String? workflowName;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (active != null) 'active': active,
        if (bucket != null) 'bucket': bucket,
        if (config != null) 'config': config,
        if (eventTypes != null) 'eventTypes': eventTypes,
        if (fileSuffixes != null) 'fileSuffixes': fileSuffixes,
        if (pipelineType != null) 'pipelineType': pipelineType,
        if (prefix != null) 'prefix': prefix,
        if (workflowId != null) 'workflowId': workflowId,
        if (workflowName != null) 'workflowName': workflowName,
      };
}

/// One run of a folder automation rule (`model.ProcessingJob`).
class ProcessingJob extends BaseEntity {
  const ProcessingJob({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.deletedBy,
    super.createdAt,
    super.updatedAt,
    super.deletedAt,
    super.prn,
    this.attempts,
    this.bucket,
    this.error,
    this.eventType,
    this.folderConfigId,
    this.key,
    this.nodeId,
    this.pipelineType,
    this.result,
    this.status,
  });

  factory ProcessingJob.fromJson(Map<String, dynamic> json) => ProcessingJob(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        deletedBy: readString(json['deletedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        deletedAt: readString(json['deletedAt']),
        prn: readString(json['prn']),
        attempts: readInt(json['attempts']),
        bucket: readString(json['bucket']),
        error: readString(json['error']),
        eventType: readString(json['eventType']),
        folderConfigId: readString(json['folderConfigId']),
        key: readString(json['key']),
        nodeId: readString(json['nodeId']),
        pipelineType: readString(json['pipelineType']),
        result: readMap(json['result']),
        status: readString(json['status']),
      );

  final int? attempts;

  final String? bucket;

  final String? error;

  /// One of `create`, `update`, `delete`.
  final String? eventType;

  final String? folderConfigId;

  final String? key;

  final String? nodeId;

  /// One of `custom_workflow`, `extract_text`, `ocr`, `summarize`, `classify_tag`, `kb_ingest`,
  /// `thumbnail`.
  final String? pipelineType;

  final Map<String, dynamic>? result;

  /// One of `queued`, `dispatched`, `succeeded`, `failed`.
  final String? status;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (attempts != null) 'attempts': attempts,
        if (bucket != null) 'bucket': bucket,
        if (error != null) 'error': error,
        if (eventType != null) 'eventType': eventType,
        if (folderConfigId != null) 'folderConfigId': folderConfigId,
        if (key != null) 'key': key,
        if (nodeId != null) 'nodeId': nodeId,
        if (pipelineType != null) 'pipelineType': pipelineType,
        if (result != null) 'result': result,
        if (status != null) 'status': status,
      };
}

/// A file stored under `.apps/{appKey}/` (`api.AppFileUpload`).
class AppFileUpload {
  const AppFileUpload({
    this.appKey,
    this.contentType,
    this.name,
    this.nodeId,
    this.path,
    this.permalink,
    this.publicUrl,
    this.signedUrl,
    this.size,
  });

  factory AppFileUpload.fromJson(Map<String, dynamic> json) => AppFileUpload(
        appKey: readString(json['appKey']),
        contentType: readString(json['contentType']),
        name: readString(json['name']),
        nodeId: readString(json['nodeId']),
        path: readString(json['path']),
        permalink: readString(json['permalink']),
        publicUrl: readString(json['publicUrl']),
        signedUrl: readString(json['signedUrl']),
        size: readInt(json['size']),
      );

  final String? appKey;

  final String? contentType;

  final String? name;

  /// NodeID and Permalink are absent when the node index is unavailable.
  final String? nodeId;

  final String? path;

  /// Permalink survives renames: store it instead of a storage URL.
  final String? permalink;

  final String? publicUrl;

  /// SignedURL is present only when presigning is enabled.
  final String? signedUrl;

  final int? size;

  Map<String, dynamic> toJson() => {
        if (appKey != null) 'appKey': appKey,
        if (contentType != null) 'contentType': contentType,
        if (name != null) 'name': name,
        if (nodeId != null) 'nodeId': nodeId,
        if (path != null) 'path': path,
        if (permalink != null) 'permalink': permalink,
        if (publicUrl != null) 'publicUrl': publicUrl,
        if (signedUrl != null) 'signedUrl': signedUrl,
        if (size != null) 'size': size,
      };
}

/// Report of an app retention sweep (`api.AppFilesSweep`). With no archive tier configured,
/// [skipped] is true, [reason] says why and nothing changes.
class AppFilesSweep {
  const AppFilesSweep({
    this.archived,
    this.candidates,
    this.failed,
    this.olderThan,
    this.prefix,
    this.reason,
    this.skipped,
  });

  factory AppFilesSweep.fromJson(Map<String, dynamic> json) => AppFilesSweep(
        archived: readInt(json['archived']),
        candidates: readInt(json['candidates']),
        failed: readInt(json['failed']),
        olderThan: readString(json['olderThan']),
        prefix: readString(json['prefix']),
        reason: readString(json['reason']),
        skipped: readBool(json['skipped']),
      );

  final int? archived;

  final int? candidates;

  final int? failed;

  final String? olderThan;

  final String? prefix;

  final String? reason;

  final bool? skipped;

  Map<String, dynamic> toJson() => {
        if (archived != null) 'archived': archived,
        if (candidates != null) 'candidates': candidates,
        if (failed != null) 'failed': failed,
        if (olderThan != null) 'olderThan': olderThan,
        if (prefix != null) 'prefix': prefix,
        if (reason != null) 'reason': reason,
        if (skipped != null) 'skipped': skipped,
      };
}

/// Runs a workflow when a matching object event happens (`model.Trigger`).
class Trigger extends BaseEntity {
  const Trigger({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.deletedBy,
    super.createdAt,
    super.updatedAt,
    super.deletedAt,
    super.prn,
    this.active,
    this.eventType,
    this.prefix,
    this.suffix,
    this.workflowId,
    this.workflowName,
  });

  factory Trigger.fromJson(Map<String, dynamic> json) => Trigger(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        deletedBy: readString(json['deletedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        deletedAt: readString(json['deletedAt']),
        prn: readString(json['prn']),
        active: readBool(json['active']),
        eventType: readString(json['eventType']),
        prefix: readString(json['prefix']),
        suffix: readString(json['suffix']),
        workflowId: readString(json['workflowId']),
        workflowName: readString(json['workflowName']),
      );

  final bool? active;

  /// One of `create`, `update`, `delete`.
  final String? eventType;

  final String? prefix;

  final String? suffix;

  final String? workflowId;

  final String? workflowName;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (active != null) 'active': active,
        if (eventType != null) 'eventType': eventType,
        if (prefix != null) 'prefix': prefix,
        if (suffix != null) 'suffix': suffix,
        if (workflowId != null) 'workflowId': workflowId,
        if (workflowName != null) 'workflowName': workflowName,
      };
}

/// Calls a URL when a matching object event happens (`model.Webhook`).
class Webhook extends BaseEntity {
  const Webhook({
    super.id,
    super.orgId,
    super.createdBy,
    super.updatedBy,
    super.deletedBy,
    super.createdAt,
    super.updatedAt,
    super.deletedAt,
    super.prn,
    this.active,
    this.eventTypes,
    this.headers,
    this.method,
    this.prefix,
    this.suffix,
    this.url,
  });

  factory Webhook.fromJson(Map<String, dynamic> json) => Webhook(
        id: readString(json['id']),
        orgId: readString(json['orgId']),
        createdBy: readString(json['createdBy']),
        updatedBy: readString(json['updatedBy']),
        deletedBy: readString(json['deletedBy']),
        createdAt: readString(json['createdAt']),
        updatedAt: readString(json['updatedAt']),
        deletedAt: readString(json['deletedAt']),
        prn: readString(json['prn']),
        active: readBool(json['active']),
        eventTypes: readStringList(json['eventTypes']),
        headers: readStringMap(json['headers']),
        method: readString(json['method']),
        prefix: readString(json['prefix']),
        suffix: readString(json['suffix']),
        url: readString(json['url']),
      );

  final bool? active;

  /// One of `create`, `update`, `delete`.
  final List<String>? eventTypes;

  final Map<String, String>? headers;

  final String? method;

  final String? prefix;

  final String? suffix;

  /// Uniqueness is (org_id, url) — enforced by idx_webhooks_org_url created in runMigrations; a
  /// bare unique url would collide across tenants.
  final String? url;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (active != null) 'active': active,
        if (eventTypes != null) 'eventTypes': eventTypes,
        if (headers != null) 'headers': headers,
        if (method != null) 'method': method,
        if (prefix != null) 'prefix': prefix,
        if (suffix != null) 'suffix': suffix,
        if (url != null) 'url': url,
      };
}

/// Current state of a file whose conditional save failed with `412` (`api.PreconditionState`).
/// Read it from `DocsException.precondition`.
class PreconditionState {
  const PreconditionState({
    this.currentEtag,
    this.updatedAt,
    this.updatedBy,
  });

  factory PreconditionState.fromJson(Map<String, dynamic> json) => PreconditionState(
        currentEtag: readString(json['currentEtag']),
        updatedAt: readString(json['updatedAt']),
        updatedBy: readString(json['updatedBy']),
      );

  final String? currentEtag;

  /// ISO-8601 timestamp of the last update.
  final String? updatedAt;

  /// User who last updated the entity.
  final String? updatedBy;

  Map<String, dynamic> toJson() => {
        if (currentEtag != null) 'currentEtag': currentEtag,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (updatedBy != null) 'updatedBy': updatedBy,
      };
}

/// The `error` object of a failed response (`api.ErrorBody`): [message] is a short code (e.g.
/// `AAS-00106`) or text, [details] the human-readable reason.
class ErrorBody {
  const ErrorBody({
    this.code,
    this.details,
    this.message,
  });

  factory ErrorBody.fromJson(Map<String, dynamic> json) => ErrorBody(
        code: readInt(json['code']),
        details: readString(json['details']),
        message: readString(json['message']),
      );

  final int? code;

  final String? details;

  final String? message;

  Map<String, dynamic> toJson() => {
        if (code != null) 'code': code,
        if (details != null) 'details': details,
        if (message != null) 'message': message,
      };
}

/// Body of `folders.create` (`api.CreateFolderRequest`). A nested [folderName] (`a/b/c`) creates
/// every missing level.
class CreateFolderRequest {
  const CreateFolderRequest({
    required this.folderName,
    this.parentName,
  });

  factory CreateFolderRequest.fromJson(Map<String, dynamic> json) => CreateFolderRequest(
        folderName: readString(json['folderName']) ?? '',
        parentName: readString(json['parentName']),
      );

  /// Folder to create; a nested name (`a/b/c`) creates every missing level.
  final String folderName;

  /// ParentName is the folder to create in ("" = library root).
  final String? parentName;

  Map<String, dynamic> toJson() => {
        'folderName': folderName,
        if (parentName != null) 'parentName': parentName,
      };
}

/// Body of `files.rename` / `folders.rename` (`api.RenameRequest`): renames (or moves, when
/// [newName] holds a path) the item [oldName] that lives in [parentName].
class RenameRequest {
  const RenameRequest({
    required this.newName,
    required this.oldName,
    this.parentName,
  });

  factory RenameRequest.fromJson(Map<String, dynamic> json) => RenameRequest(
        newName: readString(json['newName']) ?? '',
        oldName: readString(json['oldName']) ?? '',
        parentName: readString(json['parentName']),
      );

  /// New name, or a path to move the item to.
  final String newName;

  /// Current name of the item.
  final String oldName;

  /// Folder holding the item (empty = library root).
  final String? parentName;

  Map<String, dynamic> toJson() => {
        'newName': newName,
        'oldName': oldName,
        if (parentName != null) 'parentName': parentName,
      };
}

/// Body of `files.createBlank` (`api.CreateBlankFileRequest`): creates an empty file.
class CreateBlankFileRequest {
  const CreateBlankFileRequest({
    required this.fileName,
    this.parentName,
  });

  factory CreateBlankFileRequest.fromJson(Map<String, dynamic> json) => CreateBlankFileRequest(
        fileName: readString(json['fileName']) ?? '',
        parentName: readString(json['parentName']),
      );

  /// Name of the file to create.
  final String fileName;

  /// Folder to create the file in (empty = library root).
  final String? parentName;

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        if (parentName != null) 'parentName': parentName,
      };
}

/// Body of `files.update` / `files.updateAt` (`api.UpdateFileRequest`): saves a text file's whole
/// body.
class UpdateFileRequest {
  const UpdateFileRequest({
    required this.content,
    required this.fileName,
    this.id,
    this.ifMatch,
    this.ifNoneMatch,
    this.parentName,
  });

  factory UpdateFileRequest.fromJson(Map<String, dynamic> json) => UpdateFileRequest(
        content: readString(json['content']) ?? '',
        fileName: readString(json['fileName']) ?? '',
        id: readString(json['id']),
        ifMatch: readString(json['ifMatch']),
        ifNoneMatch: readString(json['ifNoneMatch']),
        parentName: readString(json['parentName']),
      );

  /// The file's whole new body.
  final String content;

  /// Name of the file.
  final String fileName;

  /// ID is ignored on input; the response carries the real node id.
  final String? id;

  /// IfMatch is the etag last read: the save fails with 412 when the file is missing or its etag
  /// differs. Send at most one of ifMatch/ifNoneMatch; neither = unconditional save.
  final String? ifMatch;

  /// IfNoneMatch "*" (the only value accepted) makes the save create-only.
  final String? ifNoneMatch;

  /// Folder holding the file (empty = library root).
  final String? parentName;

  Map<String, dynamic> toJson() => {
        'content': content,
        'fileName': fileName,
        if (id != null) 'id': id,
        if (ifMatch != null) 'ifMatch': ifMatch,
        if (ifNoneMatch != null) 'ifNoneMatch': ifNoneMatch,
        if (parentName != null) 'parentName': parentName,
      };
}

/// Body of `folders.duplicate` (`api.DuplicateRequest`): copies a file or folder next to itself.
class DuplicateRequest {
  const DuplicateRequest({
    required this.path,
    this.type,
  });

  factory DuplicateRequest.fromJson(Map<String, dynamic> json) => DuplicateRequest(
        path: readString(json['path']) ?? '',
        type: readString(json['type']),
      );

  /// Path of the item to copy.
  final String path;

  /// One of `file`, `folder`.
  final String? type;

  Map<String, dynamic> toJson() => {
        'path': path,
        if (type != null) 'type': type,
      };
}

/// Body of `library.starPath` (`api.StarByPathRequest`).
class StarByPathRequest {
  const StarByPathRequest({
    required this.path,
    this.type,
  });

  factory StarByPathRequest.fromJson(Map<String, dynamic> json) => StarByPathRequest(
        path: readString(json['path']) ?? '',
        type: readString(json['type']),
      );

  /// Path of the item to star.
  final String path;

  /// One of `file`, `folder`.
  final String? type;

  Map<String, dynamic> toJson() => {
        'path': path,
        if (type != null) 'type': type,
      };
}

/// Body of `sharing.create` (`api.CreateShareRequest`): grants a member (or the whole org) access
/// to a My Drive item.
class CreateShareRequest {
  const CreateShareRequest({
    required this.path,
    required this.role,
    required this.subjectType,
    this.expiresAt,
    this.subjectId,
    this.type,
  });

  factory CreateShareRequest.fromJson(Map<String, dynamic> json) => CreateShareRequest(
        path: readString(json['path']) ?? '',
        role: readString(json['role']) ?? '',
        subjectType: readString(json['subjectType']) ?? '',
        expiresAt: readString(json['expiresAt']),
        subjectId: readString(json['subjectId']),
        type: readString(json['type']),
      );

  /// Path of the My Drive item to share.
  final String path;

  /// One of `viewer`, `editor`.
  final String role;

  /// One of `user`, `org`.
  final String subjectType;

  /// ExpiresAt is an optional RFC3339 expiry.
  final String? expiresAt;

  /// SubjectID is the grantee's user id; required for user shares, ignored for org shares.
  final String? subjectId;

  /// One of `file`, `folder`.
  final String? type;

  Map<String, dynamic> toJson() => {
        'path': path,
        'role': role,
        'subjectType': subjectType,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (subjectId != null) 'subjectId': subjectId,
        if (type != null) 'type': type,
      };
}

/// Body of `sharing.createLink` (`api.CreateShareLinkRequest`): mints an org-scope link for a My
/// Drive file.
class CreateShareLinkRequest {
  const CreateShareLinkRequest({
    required this.path,
    this.expiresAt,
    this.type,
  });

  factory CreateShareLinkRequest.fromJson(Map<String, dynamic> json) => CreateShareLinkRequest(
        path: readString(json['path']) ?? '',
        expiresAt: readString(json['expiresAt']),
        type: readString(json['type']),
      );

  /// Path of the My Drive file to link.
  final String path;

  /// ExpiresAt is an optional RFC3339 expiry.
  final String? expiresAt;

  /// One of `file`.
  final String? type;

  Map<String, dynamic> toJson() => {
        'path': path,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (type != null) 'type': type,
      };
}

/// Body of `automation.create` / `automation.update` (`api.FolderConfigRequest`): an automation
/// rule on a folder.
class FolderConfigRequest {
  const FolderConfigRequest({
    required this.pipelineType,
    required this.prefix,
    this.active,
    this.config,
    this.eventTypes,
    this.fileSuffixes,
    this.workflowId,
    this.workflowName,
  });

  factory FolderConfigRequest.fromJson(Map<String, dynamic> json) => FolderConfigRequest(
        pipelineType: readString(json['pipelineType']) ?? '',
        prefix: readString(json['prefix']) ?? '',
        active: readBool(json['active']),
        config: readMap(json['config']),
        eventTypes: readStringList(json['eventTypes']),
        fileSuffixes: readStringList(json['fileSuffixes']),
        workflowId: readString(json['workflowId']),
        workflowName: readString(json['workflowName']),
      );

  /// One of `custom_workflow`, `extract_text`, `thumbnail`.
  final String pipelineType;

  /// Prefix is the watched folder; a trailing "/" is added when missing.
  final String prefix;

  /// Active defaults to true when omitted.
  final bool? active;

  /// Config is free-form pipeline configuration stored with the rule.
  final Map<String, dynamic>? config;

  /// EventTypes filters which events run the pipeline; empty = create only. One of `create`,
  /// `update`.
  final List<String>? eventTypes;

  /// Only files with these suffixes run (e.g. `.pdf`); empty = all.
  final List<String>? fileSuffixes;

  /// Workflow run by the rule; required for `custom_workflow`.
  final String? workflowId;

  /// Display name of the workflow.
  final String? workflowName;

  Map<String, dynamic> toJson() => {
        'pipelineType': pipelineType,
        'prefix': prefix,
        if (active != null) 'active': active,
        if (config != null) 'config': config,
        if (eventTypes != null) 'eventTypes': eventTypes,
        if (fileSuffixes != null) 'fileSuffixes': fileSuffixes,
        if (workflowId != null) 'workflowId': workflowId,
        if (workflowName != null) 'workflowName': workflowName,
      };
}

/// Body of `appFiles.sweep` (`api.SweepRequest`): archives an app's files under [prefix] older
/// than [olderThanDays].
class SweepRequest {
  const SweepRequest({
    this.limit,
    this.olderThanDays,
    this.prefix,
  });

  factory SweepRequest.fromJson(Map<String, dynamic> json) => SweepRequest(
        limit: readInt(json['limit']),
        olderThanDays: readInt(json['olderThanDays']),
        prefix: readString(json['prefix']),
      );

  /// Limit caps the files archived in one sweep (<= 0 = 500).
  final int? limit;

  /// OlderThanDays <= 0 uses the archive tier's configured retention.
  final int? olderThanDays;

  /// Folder inside the app area to sweep.
  final String? prefix;

  Map<String, dynamic> toJson() => {
        if (limit != null) 'limit': limit,
        if (olderThanDays != null) 'olderThanDays': olderThanDays,
        if (prefix != null) 'prefix': prefix,
      };
}

/// Body of `triggers.create` / `triggers.update` (`api.TriggerRequest`). The server stores
/// [active] as sent, so an omitted value creates an inactive trigger.
class TriggerRequest {
  const TriggerRequest({
    required this.prefix,
    required this.workflowId,
    this.active,
    this.eventType,
    this.suffix,
    this.workflowName,
  });

  factory TriggerRequest.fromJson(Map<String, dynamic> json) => TriggerRequest(
        prefix: readString(json['prefix']) ?? '',
        workflowId: readString(json['workflowId']) ?? '',
        active: readBool(json['active']),
        eventType: readString(json['eventType']),
        suffix: readString(json['suffix']),
        workflowName: readString(json['workflowName']),
      );

  /// Folder the trigger watches.
  final String prefix;

  /// Workflow to run.
  final String workflowId;

  /// Whether the trigger fires; the server stores `false` when omitted.
  final bool? active;

  /// One of `create`, `update`, `delete`.
  final String? eventType;

  /// Only keys ending with this suffix (e.g. `.pdf`).
  final String? suffix;

  /// Display name of the workflow.
  final String? workflowName;

  Map<String, dynamic> toJson() => {
        'prefix': prefix,
        'workflowId': workflowId,
        if (active != null) 'active': active,
        if (eventType != null) 'eventType': eventType,
        if (suffix != null) 'suffix': suffix,
        if (workflowName != null) 'workflowName': workflowName,
      };
}

/// Body of `webhooks.create` / `webhooks.update` (`api.WebhookRequest`). The server stores
/// [active] as sent, so an omitted value creates an inactive webhook.
class WebhookRequest {
  const WebhookRequest({
    required this.eventTypes,
    required this.method,
    required this.prefix,
    required this.url,
    this.active,
    this.headers,
    this.suffix,
  });

  factory WebhookRequest.fromJson(Map<String, dynamic> json) => WebhookRequest(
        eventTypes: readStringList(json['eventTypes']) ?? const <String>[],
        method: readString(json['method']) ?? '',
        prefix: readString(json['prefix']) ?? '',
        url: readString(json['url']) ?? '',
        active: readBool(json['active']),
        headers: readStringMap(json['headers']),
        suffix: readString(json['suffix']),
      );

  /// EventTypes accepts create, update and delete (a comma-joined entry is split). One of `create`,
  /// `update`, `delete`.
  final List<String> eventTypes;

  /// HTTP method of the delivery (e.g. `POST`).
  final String method;

  /// Folder the webhook watches.
  final String prefix;

  /// URL called on every matching event.
  final String url;

  /// Whether the webhook fires; the server stores `false` when omitted.
  final bool? active;

  /// Headers are sent with every delivery; non-string values are stringified.
  final Map<String, String>? headers;

  /// Only keys ending with this suffix (e.g. `.png`).
  final String? suffix;

  Map<String, dynamic> toJson() => {
        'eventTypes': eventTypes,
        'method': method,
        'prefix': prefix,
        'url': url,
        if (active != null) 'active': active,
        if (headers != null) 'headers': headers,
        if (suffix != null) 'suffix': suffix,
      };
}
