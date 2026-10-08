import type { HttpClient } from "../client.js";
import { DocsError, appendFile, encodePath, encodeSegment } from "../client.js";
import type {
  Binary,
  CreateFolderRequest,
  Document,
  DuplicateRequest,
  ListAtOptions,
  ListFolderOptions,
  RenameRequest,
  UploadFolderOptions,
  UploadFolderResult,
  UploadInput
} from "../types.js";
import { bucketPath } from "./paths.js";

/** Folder listings, folder CRUD, folder uploads and zip downloads. */
export class FoldersResource {
  constructor(private readonly http: HttpClient) {}

  /** Lists the direct children of `prefix` (the library root when empty) (`GET /{bucketName}/objects`). */
  list(bucketName: string, options?: ListFolderOptions): Promise<Document[]> {
    return this.http.request("GET", bucketPath(bucketName, "/objects"), undefined, {
      query: { prefix: options?.prefix, sizes: options?.sizes }
    });
  }

  /** Same listing as {@link FoldersResource.list}, addressed by path (`GET /{bucketName}/objects/{path}`). */
  listAt(bucketName: string, path: string, options?: ListAtOptions): Promise<Document[]> {
    return this.http.request("GET", bucketPath(bucketName, `/objects/${encodePath(path)}`), undefined, {
      query: { sizes: options?.sizes }
    });
  }

  /** Lists an org-library folder (`GET /{bucketName}/public/objects`). */
  listPublic(bucketName: string, options?: ListFolderOptions): Promise<Document[]> {
    return this.http.request("GET", bucketPath(bucketName, "/public/objects"), undefined, {
      query: { prefix: options?.prefix, sizes: options?.sizes }
    });
  }

  /** Lists `.users/{userId}/{prefix}`, a personal drive (`GET /{bucketName}/users/{userId}/objects`). */
  listUser(bucketName: string, userId: string, options?: ListFolderOptions): Promise<Document[]> {
    return this.http.request(
      "GET",
      bucketPath(bucketName, `/users/${encodeSegment(userId)}/objects`),
      undefined,
      { query: { prefix: options?.prefix, sizes: options?.sizes } }
    );
  }

  /** Lists `.apps/{appId}/{prefix}`, an app's data folder (`GET /{bucketName}/apps/{appId}/objects`). */
  listApp(bucketName: string, appId: string, options?: ListFolderOptions): Promise<Document[]> {
    return this.http.request(
      "GET",
      bucketPath(bucketName, `/apps/${encodeSegment(appId)}/objects`),
      undefined,
      { query: { prefix: options?.prefix, sizes: options?.sizes } }
    );
  }

  /** Raw listing of a folder named by one path segment (`GET /{bucketName}/folder/{key}`). */
  get(bucketName: string, key: string): Promise<Document[]> {
    return this.http.request("GET", bucketPath(bucketName, `/folder/${encodeSegment(key)}`));
  }

  /** Creates a folder; returns every level created, outermost first (`POST /{bucketName}/folder`). */
  create(bucketName: string, body: CreateFolderRequest): Promise<Document[]> {
    return this.http.request("POST", bucketPath(bucketName, "/folder"), body);
  }

  /** Deletes a top-level folder named by one path segment (`DELETE /{bucketName}/folder/{key}`). */
  delete(bucketName: string, key: string): Promise<string> {
    return this.http.request("DELETE", bucketPath(bucketName, `/folder/${encodeSegment(key)}`));
  }

  /** Deletes a folder at any depth (`DELETE /{bucketName}/folder?path=`). */
  deleteByPath(bucketName: string, path: string): Promise<string> {
    return this.http.request("DELETE", bucketPath(bucketName, "/folder"), undefined, { query: { path } });
  }

  /**
   * Uploads many files (multipart: repeated `files` parts with matching
   * `relativePaths`, plus `parentID` and `prefix`) (`POST /{bucketName}/upload-folder`).
   */
  upload(bucketName: string, files: UploadInput[], options?: UploadFolderOptions): Promise<UploadFolderResult> {
    const relativePaths = options?.relativePaths;
    if (relativePaths && relativePaths.length !== files.length) {
      return Promise.reject(
        new DocsError(
          `relativePaths has ${relativePaths.length} entries for ${files.length} files; pass one per file, in order.`,
          0,
          null
        )
      );
    }
    const form = new FormData();
    for (const file of files) {
      appendFile(form, "files", file);
    }
    for (const relativePath of relativePaths ?? []) {
      form.append("relativePaths", relativePath);
    }
    if (options?.parentId !== undefined) form.append("parentID", options.parentId);
    if (options?.prefix !== undefined) form.append("prefix", options.prefix);
    return this.http.upload(bucketPath(bucketName, "/upload-folder"), form);
  }

  /** Downloads every object under a folder as a zip (`GET /{bucketName}/folder-zip/{path}`). */
  downloadZip(bucketName: string, path: string): Promise<Binary> {
    return this.http.requestBinary("GET", bucketPath(bucketName, `/folder-zip/${encodePath(path)}`));
  }

  /** Copies a file or folder next to itself as "<name> copy" (`POST /{bucketName}/duplicate`). */
  duplicate(bucketName: string, body: DuplicateRequest): Promise<Document> {
    return this.http.request("POST", bucketPath(bucketName, "/duplicate"), body);
  }

  /** Renames or moves a folder (`PUT /{bucketName}/folder/rename`). */
  rename(bucketName: string, body: RenameRequest): Promise<Document> {
    return this.http.request("PUT", bucketPath(bucketName, "/folder/rename"), body);
  }
}
