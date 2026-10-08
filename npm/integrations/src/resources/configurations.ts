import type { HttpClient } from "../client.js";
import type { ApplicationSubType, ApplicationType } from "../types.js";

export class ConfigurationsResource {
  constructor(private readonly http: HttpClient) {}

  get(): Promise<Record<ApplicationType, ApplicationSubType[]>> {
    return this.http.request("GET", "/v1/integrations/configurations");
  }
}
