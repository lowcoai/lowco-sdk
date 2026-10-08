import { HttpClient } from "./client.js";
import { AppFilesResource } from "./resources/appFiles.js";
import { AutomationResource } from "./resources/automation.js";
import { BucketsResource } from "./resources/buckets.js";
import { FilesResource } from "./resources/files.js";
import { FoldersResource } from "./resources/folders.js";
import { LibraryResource } from "./resources/library.js";
import { NodesResource } from "./resources/nodes.js";
import { bucketPath } from "./resources/paths.js";
import { SharingResource } from "./resources/sharing.js";
import { TriggersResource } from "./resources/triggers.js";
import { WebhooksResource } from "./resources/webhooks.js";
import type { DocsClientConfig, Document } from "./types.js";

/**
 * Client for the lowco document service (`https://api.lowco.ai/v1/documents`).
 * Every request carries `Authorization: Bearer <token>` and `X-Org-Id: <orgId>`.
 */
export class DocsClient {
  /** The org's bucket and its storage usage. */
  readonly buckets: BucketsResource;
  /** Folder listings, folder CRUD, folder uploads and zip downloads. */
  readonly folders: FoldersResource;
  /** File reads, saves, uploads, renames, deletes and signed URLs. */
  readonly files: FilesResource;
  /** Node metadata and permalinks. */
  readonly nodes: NodesResource;
  /** Starred items, recent items and trash. */
  readonly library: LibraryResource;
  /** Share grants, share links and items shared with the caller. */
  readonly sharing: SharingResource;
  /** Folder automations and their run history. */
  readonly automation: AutomationResource;
  /** App data under `.apps/{appKey}/`. */
  readonly appFiles: AppFilesResource;
  /** Triggers that run a workflow on object events. */
  readonly triggers: TriggersResource;
  /** Webhooks called on object events. */
  readonly webhooks: WebhooksResource;

  private readonly http: HttpClient;

  /** Throws when `token` or `orgId` is missing or blank. */
  constructor(config: DocsClientConfig) {
    const http = new HttpClient(config);
    this.http = http;
    this.buckets = new BucketsResource(http);
    this.folders = new FoldersResource(http);
    this.files = new FilesResource(http);
    this.nodes = new NodesResource(http);
    this.library = new LibraryResource(http);
    this.sharing = new SharingResource(http);
    this.automation = new AutomationResource(http);
    this.appFiles = new AppFilesResource(http);
    this.triggers = new TriggersResource(http);
    this.webhooks = new WebhooksResource(http);
  }

  /** Liveness probe; resolves to the service's text answer, "Working!" (`GET /health`, outside `/v1/documents`). */
  health(): Promise<string> {
    return this.http.requestText("GET", "/health");
  }

  /**
   * Finds files and folders whose name matches `q`, then documents whose
   * extracted text matches (`metadata.matchedBy = "content"`) (`GET /{bucketName}/search?q=`).
   */
  search(bucketName: string, q: string): Promise<Document[]> {
    return this.http.request("GET", bucketPath(bucketName, "/search"), undefined, { query: { q } });
  }
}

export { HttpClient, DocsError, HEADER_ORG_ID } from "./client.js";
export * from "./types.js";
