import type { ServiceTarget, Transport } from "./transport.js";
import type {
  Dataset,
  EmbeddingDbRequest,
  KnowledgeBase,
  ListParams,
} from "./types.js";

/** Exposes the agent-kb (knowledge-base) service routes. */
export class KBClient {
  constructor(
    private readonly transport: Transport,
    private readonly target: ServiceTarget,
  ) {}

  private path(...parts: string[]): string {
    return this.transport.joinPath(this.target.apiBasePath, ...parts);
  }

  // --- Health ------------------------------------------------------------

  async health(): Promise<void> {
    await this.transport.request<void>(this.target, {
      method: "GET",
      path: "/health",
      enveloped: false,
    });
  }

  // --- Knowledge bases ---------------------------------------------------

  listKnowledgeBases(params?: ListParams): Promise<KnowledgeBase[]> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("knowledges"),
      query: this.transport.listQuery(params),
      enveloped: true,
    });
  }
  createKnowledgeBase(kb: KnowledgeBase): Promise<KnowledgeBase> {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("knowledges"),
      body: kb,
      enveloped: true,
    });
  }
  getKnowledgeBase(id: string): Promise<KnowledgeBase> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("knowledges", id),
      enveloped: true,
    });
  }
  updateKnowledgeBase(id: string, kb: KnowledgeBase): Promise<KnowledgeBase> {
    return this.transport.request(this.target, {
      method: "PUT",
      path: this.path("knowledges", id),
      body: kb,
      enveloped: true,
    });
  }
  /** The /knowledges/count endpoint returns a raw integer, not an envelope. */
  getKnowledgeBaseCount(params?: ListParams): Promise<number> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("knowledges", "count"),
      query: this.transport.listQuery(params),
      enveloped: false,
    });
  }

  // --- Datasets ----------------------------------------------------------

  listDatasets(params?: ListParams): Promise<Dataset[]> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("datasets"),
      query: this.transport.listQuery(params),
      enveloped: true,
    });
  }
  createDataset(dataset: Dataset): Promise<Dataset> {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("datasets"),
      body: dataset,
      enveloped: true,
    });
  }
  getDataset(id: string): Promise<Dataset> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("datasets", id),
      enveloped: true,
    });
  }
  updateDataset(id: string, dataset: Dataset): Promise<Dataset> {
    return this.transport.request(this.target, {
      method: "PUT",
      path: this.path("datasets", id),
      body: dataset,
      enveloped: true,
    });
  }
  async deleteDataset(id: string): Promise<void> {
    await this.transport.request<void>(this.target, {
      method: "DELETE",
      path: this.path("datasets", id),
      enveloped: false,
    });
  }
  /** The /datasets/count endpoint returns a raw integer, not an envelope. */
  getDatasetCount(params?: ListParams): Promise<number> {
    return this.transport.request(this.target, {
      method: "GET",
      path: this.path("datasets", "count"),
      query: this.transport.listQuery(params),
      enveloped: false,
    });
  }

  // --- Embeddings --------------------------------------------------------

  /** Persists embeddings into the vector store; returns the service's success message. */
  storeEmbeddings(req: EmbeddingDbRequest): Promise<string> {
    return this.transport.request(this.target, {
      method: "POST",
      path: this.path("embeddings"),
      body: req,
      enveloped: true,
    });
  }
}
