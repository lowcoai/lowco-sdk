import type { HttpClient } from "../client.js";
import { API_PREFIX } from "../client.js";
import type { BucketStats, Document } from "../types.js";
import { bucketPath } from "./paths.js";

/** The org's bucket and its storage usage. */
export class BucketsResource {
  constructor(private readonly http: HttpClient) {}

  /**
   * Returns the bucket of the configured org (created on first use) as a folder
   * document; its `name` is the bucket name the other methods take
   * (`GET /v1/documents`).
   */
  get(): Promise<Document> {
    return this.http.request("GET", API_PREFIX);
  }

  /** Storage usage of a bucket, split between visible and system content (`GET /{bucketName}/stats`). */
  stats(bucketName: string): Promise<BucketStats> {
    return this.http.request("GET", bucketPath(bucketName, "/stats"));
  }
}
