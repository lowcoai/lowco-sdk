import type { HttpClient } from "../client.js";
import { encodeSegment } from "../client.js";
import type { FolderConfig, FolderConfigRequest, JobsOptions, PrefixOptions, ProcessingJob } from "../types.js";
import { bucketPath } from "./paths.js";

/** Folder automations (pipelines that run on files added under a folder) and their run history. */
export class AutomationResource {
  constructor(private readonly http: HttpClient) {}

  /** The bucket's automation rules visible to the caller, optionally for one folder (`GET /{bucketName}/folder-configs`). */
  list(bucketName: string, options?: PrefixOptions): Promise<FolderConfig[]> {
    return this.http.request("GET", bucketPath(bucketName, "/folder-configs"), undefined, {
      query: { prefix: options?.prefix }
    });
  }

  /** Creates an automation rule on a folder (`POST /{bucketName}/folder-configs`). */
  create(bucketName: string, body: FolderConfigRequest): Promise<FolderConfig> {
    return this.http.request("POST", bucketPath(bucketName, "/folder-configs"), body);
  }

  /** Returns one automation rule (`GET /{bucketName}/folder-configs/{id}`). */
  get(bucketName: string, id: string): Promise<FolderConfig> {
    return this.http.request("GET", bucketPath(bucketName, `/folder-configs/${encodeSegment(id)}`));
  }

  /** Replaces an automation rule (`PUT /{bucketName}/folder-configs/{id}`). */
  update(bucketName: string, id: string, body: FolderConfigRequest): Promise<FolderConfig> {
    return this.http.request("PUT", bucketPath(bucketName, `/folder-configs/${encodeSegment(id)}`), body);
  }

  /** Deletes an automation rule (`DELETE /{bucketName}/folder-configs/{id}`). */
  delete(bucketName: string, id: string): Promise<string> {
    return this.http.request("DELETE", bucketPath(bucketName, `/folder-configs/${encodeSegment(id)}`));
  }

  /** Pipeline run history, newest first (`GET /{bucketName}/processing-jobs`). */
  jobs(bucketName: string, options?: JobsOptions): Promise<ProcessingJob[]> {
    return this.http.request("GET", bucketPath(bucketName, "/processing-jobs"), undefined, {
      query: { configId: options?.configId, limit: options?.limit }
    });
  }
}
