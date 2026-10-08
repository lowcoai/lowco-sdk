import { API_PREFIX, encodeSegment } from "../client.js";

/** `/v1/documents/{bucketName}{rest}` with the bucket name percent-encoded. */
export function bucketPath(bucketName: string, rest = ""): string {
  return `${API_PREFIX}/${encodeSegment(bucketName)}${rest}`;
}
