package agentx

import (
	"context"
	"net/http"
	"net/url"
)

// KBClient exposes the agent-kb (knowledge-base) service routes.
// Obtain it from Client.KB.
type KBClient struct {
	c *Client
}

func (k *KBClient) path(parts ...string) string {
	return joinPath(k.c.kbBasePath, parts...)
}

func (k *KBClient) do(ctx context.Context, method, endpoint string, query url.Values, body, out any, enveloped bool) error {
	return k.c.do(ctx, k.c.kbURL, method, endpoint, query, body, out, enveloped)
}

// Health pings the agent-kb /health endpoint.
func (k *KBClient) Health(ctx context.Context) error {
	return k.do(ctx, http.MethodGet, "/health", nil, nil, nil, false)
}

// --- Knowledge bases -----------------------------------------------------

func (k *KBClient) ListKnowledgeBases(ctx context.Context, params *ListParams) ([]KnowledgeBase, error) {
	var out []KnowledgeBase
	if err := k.do(ctx, http.MethodGet, k.path("knowledges"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

func (k *KBClient) CreateKnowledgeBase(ctx context.Context, kb KnowledgeBase) (*KnowledgeBase, error) {
	var out KnowledgeBase
	if err := k.do(ctx, http.MethodPost, k.path("knowledges"), nil, kb, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (k *KBClient) GetKnowledgeBase(ctx context.Context, id string) (*KnowledgeBase, error) {
	var out KnowledgeBase
	if err := k.do(ctx, http.MethodGet, k.path("knowledges", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (k *KBClient) UpdateKnowledgeBase(ctx context.Context, id string, kb KnowledgeBase) (*KnowledgeBase, error) {
	var out KnowledgeBase
	if err := k.do(ctx, http.MethodPut, k.path("knowledges", id), nil, kb, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

// GetKnowledgeBaseCount returns a raw integer; the endpoint is not enveloped.
func (k *KBClient) GetKnowledgeBaseCount(ctx context.Context, params *ListParams) (int64, error) {
	var out int64
	if err := k.do(ctx, http.MethodGet, k.path("knowledges", "count"), params.values(), nil, &out, false); err != nil {
		return 0, err
	}
	return out, nil
}

// --- Datasets ------------------------------------------------------------

func (k *KBClient) ListDatasets(ctx context.Context, params *ListParams) ([]Dataset, error) {
	var out []Dataset
	if err := k.do(ctx, http.MethodGet, k.path("datasets"), params.values(), nil, &out, true); err != nil {
		return nil, err
	}
	return out, nil
}

func (k *KBClient) CreateDataset(ctx context.Context, dataset Dataset) (*Dataset, error) {
	var out Dataset
	if err := k.do(ctx, http.MethodPost, k.path("datasets"), nil, dataset, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (k *KBClient) GetDataset(ctx context.Context, id string) (*Dataset, error) {
	var out Dataset
	if err := k.do(ctx, http.MethodGet, k.path("datasets", id), nil, nil, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (k *KBClient) UpdateDataset(ctx context.Context, id string, dataset Dataset) (*Dataset, error) {
	var out Dataset
	if err := k.do(ctx, http.MethodPut, k.path("datasets", id), nil, dataset, &out, true); err != nil {
		return nil, err
	}
	return &out, nil
}

func (k *KBClient) DeleteDataset(ctx context.Context, id string) error {
	return k.do(ctx, http.MethodDelete, k.path("datasets", id), nil, nil, nil, false)
}

// GetDatasetCount returns a raw integer; the endpoint is not enveloped.
func (k *KBClient) GetDatasetCount(ctx context.Context, params *ListParams) (int64, error) {
	var out int64
	if err := k.do(ctx, http.MethodGet, k.path("datasets", "count"), params.values(), nil, &out, false); err != nil {
		return 0, err
	}
	return out, nil
}

// --- Embeddings ----------------------------------------------------------

// StoreEmbeddings persists embeddings for the supplied texts into the vector
// store. The response envelope's data is a plain success message string.
func (k *KBClient) StoreEmbeddings(ctx context.Context, req EmbeddingDbRequest) (string, error) {
	var out string
	if err := k.do(ctx, http.MethodPost, k.path("embeddings"), nil, req, &out, true); err != nil {
		return "", err
	}
	return out, nil
}
