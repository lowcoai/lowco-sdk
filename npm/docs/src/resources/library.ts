import type { HttpClient } from "../client.js";
import { encodeSegment } from "../client.js";
import type { Document, RecentOptions, StarByPathRequest, StarPathOptions } from "../types.js";
import { bucketPath } from "./paths.js";

/** The caller's personal library: starred items, recent items and trash. */
export class LibraryResource {
  constructor(private readonly http: HttpClient) {}

  /** Stars a node (`POST /{bucketName}/nodes/{nodeId}/star`). */
  star(bucketName: string, nodeId: string): Promise<string> {
    return this.http.request("POST", bucketPath(bucketName, `/nodes/${encodeSegment(nodeId)}/star`));
  }

  /** Removes the caller's star from a node (`DELETE /{bucketName}/nodes/{nodeId}/star`). */
  unstar(bucketName: string, nodeId: string): Promise<string> {
    return this.http.request("DELETE", bucketPath(bucketName, `/nodes/${encodeSegment(nodeId)}/star`));
  }

  /** Stars the item at a bucket path and returns it (`POST /{bucketName}/star`). */
  starPath(bucketName: string, path: string, options?: StarPathOptions): Promise<Document> {
    const body: StarByPathRequest = { path };
    if (options?.type !== undefined) body.type = options.type;
    return this.http.request("POST", bucketPath(bucketName, "/star"), body);
  }

  /** Removes the caller's star from the item at a bucket path (`DELETE /{bucketName}/star?path=`). */
  unstarPath(bucketName: string, path: string): Promise<string> {
    return this.http.request("DELETE", bucketPath(bucketName, "/star"), undefined, { query: { path } });
  }

  /** The caller's starred items that still exist and are readable (`GET /{bucketName}/starred`). */
  starred(bucketName: string): Promise<Document[]> {
    return this.http.request("GET", bucketPath(bucketName, "/starred"));
  }

  /** Items the caller recently uploaded, edited or viewed, newest first (`GET /{bucketName}/recent`). */
  recent(bucketName: string, options?: RecentOptions): Promise<Document[]> {
    return this.http.request("GET", bucketPath(bucketName, "/recent"), undefined, {
      query: { limit: options?.limit }
    });
  }

  /** Trashed items the caller may manage (`GET /{bucketName}/trash`). */
  trash(bucketName: string): Promise<Document[]> {
    return this.http.request("GET", bucketPath(bucketName, "/trash"));
  }

  /** Puts a trashed item back at its original location (`POST /{bucketName}/trash/{nodeId}/restore`). */
  restore(bucketName: string, nodeId: string): Promise<Document> {
    return this.http.request("POST", bucketPath(bucketName, `/trash/${encodeSegment(nodeId)}/restore`));
  }

  /** Permanently deletes a trashed item (`DELETE /{bucketName}/trash/{nodeId}`). */
  purge(bucketName: string, nodeId: string): Promise<string> {
    return this.http.request("DELETE", bucketPath(bucketName, `/trash/${encodeSegment(nodeId)}`));
  }
}
