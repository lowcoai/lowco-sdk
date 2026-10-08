import type { HttpClient } from "../client.js";
import { appendFile, encodePath } from "../client.js";
import type {
  ArchiveListing,
  CreateBlankFileRequest,
  Document,
  FileContent,
  ReadFileOptions,
  RenameRequest,
  UpdateFileRequest,
  UploadFileOptions,
  UploadInput
} from "../types.js";
import { bucketPath } from "./paths.js";

/** File reads, saves, uploads, renames, deletes and signed URLs. */
export class FilesResource {
  constructor(private readonly http: HttpClient) {}

  /** Returns a file's metadata, URLs and body as text, and records a view (`GET /{bucketName}/file/{path}`). */
  get(bucketName: string, path: string): Promise<Document> {
    return this.http.request("GET", bucketPath(bucketName, `/file/${encodePath(path)}`));
  }

  /**
   * Reads a file by its full key with the etag of exactly that version (send it
   * back as `ifMatch`) and the caller's role (`GET /{bucketName}/file?path=&meta=`).
   */
  read(bucketName: string, path: string, options?: ReadFileOptions): Promise<FileContent> {
    return this.http.request("GET", bucketPath(bucketName, "/file"), undefined, {
      query: { path, meta: options?.meta }
    });
  }

  /** Creates an empty file (`POST /{bucketName}/file`). */
  createBlank(bucketName: string, body: CreateBlankFileRequest): Promise<Document> {
    return this.http.request("POST", bucketPath(bucketName, "/file"), body);
  }

  /**
   * Saves a text file's whole body, creating it when missing. A stale `ifMatch`
   * fails with a 412 `DocsError` whose `payload.data` holds the current state
   * (`PUT /{bucketName}/file`).
   */
  update(bucketName: string, body: UpdateFileRequest): Promise<Document> {
    return this.http.request("PUT", bucketPath(bucketName, "/file"), body);
  }

  /** Same as {@link FilesResource.update}; the server ignores the path segment (`PUT /{bucketName}/file/{path}`). */
  updateAt(bucketName: string, path: string, body: UpdateFileRequest): Promise<Document> {
    return this.http.request("PUT", bucketPath(bucketName, `/file/${encodePath(path)}`), body);
  }

  /** Renames or moves a file; its node id, shares and permalinks survive (`PUT /{bucketName}/file/rename`). */
  rename(bucketName: string, body: RenameRequest): Promise<Document> {
    return this.http.request("PUT", bucketPath(bucketName, "/file/rename"), body);
  }

  /** Deletes a file; library and personal files move to the trash (`DELETE /{bucketName}/file/{path}`). */
  delete(bucketName: string, path: string): Promise<string> {
    return this.http.request("DELETE", bucketPath(bucketName, `/file/${encodePath(path)}`));
  }

  /** Deletes a file addressed by `?path=` (`DELETE /{bucketName}/file?path=`). */
  deleteByPath(bucketName: string, path: string): Promise<string> {
    return this.http.request("DELETE", bucketPath(bucketName, "/file"), undefined, { query: { path } });
  }

  /**
   * Uploads one file (multipart `file`, `ParentID`, `onConflict`) into the
   * folder `parentId` (`POST /{bucketName}/upload-file`).
   */
  upload(bucketName: string, file: UploadInput, options?: UploadFileOptions): Promise<Document> {
    const form = new FormData();
    appendFile(form, "file", file);
    if (options?.parentId !== undefined) form.append("ParentID", options.parentId);
    if (options?.onConflict !== undefined) form.append("onConflict", options.onConflict);
    return this.http.upload(bucketPath(bucketName, "/upload-file"), form);
  }

  /** Returns a short-lived URL that downloads the file under its real name (`GET /{bucketName}/download/{path}`, 307). */
  downloadUrl(bucketName: string, path: string): Promise<string> {
    return this.http.requestRedirectUrl("GET", bucketPath(bucketName, `/download/${encodePath(path)}`));
  }

  /** Returns the URL of a PDF rendition of the file (`GET /{bucketName}/preview/{path}`, 307). */
  previewUrl(bucketName: string, path: string): Promise<string> {
    return this.http.requestRedirectUrl("GET", bucketPath(bucketName, `/preview/${encodePath(path)}`));
  }

  /** Lists the entries of a stored .zip without extracting it (`GET /{bucketName}/archive/{path}`). */
  listArchive(bucketName: string, path: string): Promise<ArchiveListing> {
    return this.http.request("GET", bucketPath(bucketName, `/archive/${encodePath(path)}`));
  }
}
