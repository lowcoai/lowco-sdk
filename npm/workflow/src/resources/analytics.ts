import { HttpClient } from "../client.js";

export class AnalyticsResource {
  constructor(private readonly http: HttpClient) {}

  default(): Promise<Record<string, unknown>> {
    return this.http.request("GET", "/v1/wf/analytics");
  }

  getById(id: string): Promise<Record<string, unknown>> {
    return this.http.request("GET", `/v1/wf/analytics/${id}`);
  }
}
