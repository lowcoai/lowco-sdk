import type { HttpClient } from "../client.js";
import { API_PREFIX, encodeSegment } from "../client.js";
import type { NodeFileResult, NodeView, ResolveNodeOptions } from "../types.js";

/** Node metadata and permalinks (`/d/{nodeId}`), which survive renames. */
export class NodesResource {
  constructor(private readonly http: HttpClient) {}

  /** Node metadata with the caller's role (`GET /nodes/{nodeId}`). */
  get(nodeId: string): Promise<NodeView> {
    return this.http.request("GET", `${API_PREFIX}/nodes/${encodeSegment(nodeId)}`);
  }

  /**
   * Resolves a permalink without following the redirect: `url` (307), `content`
   * (200, a file restored from cold storage) or `restoring` (202, retry after
   * `retryAfter` seconds) (`GET /d/{nodeId}[?download=1]`).
   */
  resolve(nodeId: string, options?: ResolveNodeOptions): Promise<NodeFileResult> {
    return this.http.requestNodeFile(`${API_PREFIX}/d/${encodeSegment(nodeId)}`, {
      // Any value forces a download, so `false` must omit the parameter.
      query: { download: options?.download ? "1" : undefined }
    });
  }

  /** The file's bytes (`content`), or `restoring` while a cold-storage restore runs (`GET /d/{nodeId}/content`). */
  content(nodeId: string): Promise<NodeFileResult> {
    return this.http.requestNodeFile(`${API_PREFIX}/d/${encodeSegment(nodeId)}/content`);
  }
}
