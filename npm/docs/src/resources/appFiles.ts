import type { HttpClient } from "../client.js";
import { API_PREFIX, appendFile, encodePath, encodeSegment } from "../client.js";
import type {
  AppFileUpload,
  AppFileUploadOptions,
  AppFilesSweep,
  Document,
  PrefixOptions,
  SweepRequest,
  UploadInput
} from "../types.js";

/** App data under `.apps/{appKey}/` in the org's bucket (derived from `X-Org-Id`, never passed). */
export class AppFilesResource {
  constructor(private readonly http: HttpClient) {}

  /**
   * Stores a file at `.apps/{appKey}/{path}/{name}` (multipart `file`, `path`,
   * `onConflict`) and returns its node id and permalink (`POST /app-files/{appKey}`).
   */
  upload(appKey: string, file: UploadInput, options?: AppFileUploadOptions): Promise<AppFileUpload> {
    const form = new FormData();
    appendFile(form, "file", file);
    if (options?.path !== undefined) form.append("path", options.path);
    if (options?.onConflict !== undefined) form.append("onConflict", options.onConflict);
    return this.http.upload(`${API_PREFIX}/app-files/${encodeSegment(appKey)}`, form);
  }

  /** Lists the direct children of `.apps/{appKey}/{prefix}` (`GET /app-files/{appKey}/objects`). */
  list(appKey: string, options?: PrefixOptions): Promise<Document[]> {
    return this.http.request("GET", `${API_PREFIX}/app-files/${encodeSegment(appKey)}/objects`, undefined, {
      query: { prefix: options?.prefix }
    });
  }

  /** Permanently deletes `.apps/{appKey}/{path}` (`DELETE /app-files/{appKey}/{path}`). */
  delete(appKey: string, path: string): Promise<string> {
    return this.http.request("DELETE", `${API_PREFIX}/app-files/${encodeSegment(appKey)}/${encodePath(path)}`);
  }

  /** Moves the app's files older than the retention window to the archive tier (`POST /app-files/{appKey}/sweep`). */
  sweep(appKey: string, body: SweepRequest = {}): Promise<AppFilesSweep> {
    return this.http.request("POST", `${API_PREFIX}/app-files/${encodeSegment(appKey)}/sweep`, body);
  }
}
