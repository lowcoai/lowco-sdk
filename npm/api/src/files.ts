import type { FileRef } from "./core.js";

interface LocalOptions {
  /** The name to store the input under. */
  filename?: string;
  mimeType?: string;
  /** Opens a protected PDF; never stored. */
  password?: string;
}

/** Builders for file inputs. Local inputs (path, bytes, stream) are sent as multipart parts; remote ones by reference. */
export const Files = {
  /** A local file by path (read when the call is made). */
  path(path: string, options: LocalOptions = {}): FileRef {
    return { kind: "path", path, ...options };
  },
  /** Bytes, an ArrayBuffer or a Blob. */
  bytes(data: Uint8Array | ArrayBuffer | Blob, options: LocalOptions = {}): FileRef {
    return { kind: "bytes", data, ...options };
  },
  /** A Node or web stream, read to the end when the call is made. */
  stream(stream: AsyncIterable<Uint8Array> | ReadableStream<Uint8Array>, options: LocalOptions = {}): FileRef {
    return { kind: "stream", stream, ...options };
  },
  /** A public https URL the API fetches (file_url). */
  url(url: string, options: { password?: string } = {}): FileRef {
    return { kind: "url", url, ...options };
  },
  /** A stored file (file_id from files.upload or an earlier output). */
  id(fileId: string, options: { password?: string } = {}): FileRef {
    return { kind: "id", fileId, ...options };
  },
  /** Base64 or a data: URL (up to 5 MB decoded). */
  base64(data: string, options: { filename?: string; password?: string } = {}): FileRef {
    return { kind: "base64", data, ...options };
  },
};
