import type { HttpClient } from "../client.js";
import { API_PREFIX, encodeSegment } from "../client.js";
import type {
  CreateShareLinkRequest,
  CreateShareRequest,
  Document,
  Share,
  ShareLink,
  ShareLinkCreated,
  ShareQuery,
  SharedWithMeOptions
} from "../types.js";
import { bucketPath } from "./paths.js";

/** Share grants, share links and items shared with the caller. */
export class SharingResource {
  constructor(private readonly http: HttpClient) {}

  /** Grants a member (or the whole org) access to a My Drive item the caller owns (`POST /{bucketName}/shares`). */
  create(bucketName: string, body: CreateShareRequest): Promise<Share> {
    return this.http.request("POST", bucketPath(bucketName, "/shares"), body);
  }

  /** Who has access to a My Drive item; owner only (`GET /{bucketName}/shares?path=&type=`). */
  list(bucketName: string, query: ShareQuery): Promise<Share[]> {
    return this.http.request("GET", bucketPath(bucketName, "/shares"), undefined, {
      query: { path: query.path, type: query.type }
    });
  }

  /** Revokes a grant (`DELETE /{bucketName}/shares/{id}`). */
  delete(bucketName: string, id: string): Promise<string> {
    return this.http.request("DELETE", bucketPath(bucketName, `/shares/${encodeSegment(id)}`));
  }

  /** Items other members shared with the caller (`GET /{bucketName}/shared-with-me`). */
  sharedWithMe(bucketName: string, options?: SharedWithMeOptions): Promise<Document[]> {
    return this.http.request("GET", bucketPath(bucketName, "/shared-with-me"), undefined, {
      query: { appKey: options?.appKey }
    });
  }

  /** Mints an org-scope viewer link for a My Drive file (`POST /{bucketName}/share-links`). */
  createLink(bucketName: string, body: CreateShareLinkRequest): Promise<ShareLinkCreated> {
    return this.http.request("POST", bucketPath(bucketName, "/share-links"), body);
  }

  /** A file's share links; owner only (`GET /{bucketName}/share-links?path=&type=`). */
  listLinks(bucketName: string, query: ShareQuery): Promise<ShareLink[]> {
    return this.http.request("GET", bucketPath(bucketName, "/share-links"), undefined, {
      query: { path: query.path, type: query.type }
    });
  }

  /** Revokes a share link (`DELETE /{bucketName}/share-links/{id}`). */
  deleteLink(bucketName: string, id: string): Promise<string> {
    return this.http.request("DELETE", bucketPath(bucketName, `/share-links/${encodeSegment(id)}`));
  }

  /** Returns the short-lived file URL a share link redirects to (`GET /link/{token}`, 307). */
  resolveLink(token: string): Promise<string> {
    return this.http.requestRedirectUrl("GET", `${API_PREFIX}/link/${encodeSegment(token)}`);
  }
}
