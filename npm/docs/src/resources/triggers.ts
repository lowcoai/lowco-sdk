import type { HttpClient } from "../client.js";
import { API_PREFIX, encodeSegment } from "../client.js";
import type { Trigger, TriggerRequest } from "../types.js";

/** Triggers: run a workflow when an object event happens under a prefix. */
export class TriggersResource {
  constructor(private readonly http: HttpClient) {}

  /** The org's triggers visible to the caller (`GET /triggers`). */
  list(): Promise<Trigger[]> {
    return this.http.request("GET", `${API_PREFIX}/triggers`);
  }

  /** Creates a trigger; `prefix` and `workflowId` are required (`POST /triggers`). */
  create(body: TriggerRequest): Promise<Trigger> {
    return this.http.request("POST", `${API_PREFIX}/triggers`, body);
  }

  /** Returns one trigger (`GET /triggers/{id}`). */
  get(id: string): Promise<Trigger> {
    return this.http.request("GET", `${API_PREFIX}/triggers/${encodeSegment(id)}`);
  }

  /** Replaces every field of a trigger (`PUT /triggers/{id}`). */
  update(id: string, body: TriggerRequest): Promise<Trigger> {
    return this.http.request("PUT", `${API_PREFIX}/triggers/${encodeSegment(id)}`, body);
  }

  /** Deletes a trigger (`DELETE /triggers/{id}`). */
  async delete(id: string): Promise<void> {
    await this.http.request<unknown>("DELETE", `${API_PREFIX}/triggers/${encodeSegment(id)}`);
  }
}
