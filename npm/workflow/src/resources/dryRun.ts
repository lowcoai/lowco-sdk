import { HttpClient } from "../client.js";
import type { DryRunRequest } from "../types.js";

export class DryRunResource {
  constructor(private readonly http: HttpClient) {}

  execute(payload: DryRunRequest): Promise<unknown> {
    return this.http.request("POST", "/v1/wf/dryrun", payload);
  }
}
