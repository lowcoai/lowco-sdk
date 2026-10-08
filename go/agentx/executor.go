package agentx

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// ExecutorClient exposes the agent-executor service routes.
// Obtain it from Client.Executor.
type ExecutorClient struct {
	c *Client
}

func (e *ExecutorClient) path(parts ...string) string {
	return joinPath(e.c.executorBasePath, parts...)
}

// Health pings the agent-executor /health endpoint.
func (e *ExecutorClient) Health(ctx context.Context) error {
	_, _, err := e.c.doRaw(ctx, e.c.executorURL, http.MethodGet, "/health", nil, nil, "application/json")
	return err
}

// SendMessage performs a synchronous "message/send" call. The JSON-RPC id
// doubles as the target agent identifier (matching the service convention).
func (e *ExecutorClient) SendMessage(ctx context.Context, agentID string, params MessageSendParams) (*JSONRPCResponse, error) {
	req := JSONRPCRequest{
		JSONRPC: "2.0",
		Method:  MethodMessageSend,
		Params:  params,
		ID:      agentID,
	}
	body, status, err := e.c.doRaw(ctx, e.c.executorURL, http.MethodPost, e.path("execute"), nil, req, "application/json")
	if err != nil {
		return nil, err
	}
	if status == http.StatusNoContent || len(bytes.TrimSpace(body)) == 0 {
		return nil, nil
	}
	var out JSONRPCResponse
	if err := json.Unmarshal(body, &out); err != nil {
		return nil, fmt.Errorf("agentx: decode executor response: %w", err)
	}
	return &out, nil
}

// StreamEvent is a single SSE event delivered to the StreamMessage handler.
// The server emits one event per executor message; Data contains the raw JSON
// payload, which is typically an A2AMessage but may also be a tool/status frame.
type StreamEvent struct {
	Data []byte
}

// Message returns the event payload decoded into an A2AMessage. Callers that
// need to handle non-Message frames should inspect Data themselves.
func (s StreamEvent) Message() (*A2AMessage, error) {
	var m A2AMessage
	if err := json.Unmarshal(s.Data, &m); err != nil {
		return nil, err
	}
	return &m, nil
}

// StreamMessage performs a streaming "message/send" call. The handler is
// invoked for every server-sent event; returning a non-nil error from the
// handler aborts the stream. The call blocks until the server closes the
// stream, the context is cancelled, or the handler returns an error.
//
// Note: if Client uses an http.Client with a Timeout, that timeout still
// applies to the streaming connection. Configure a streaming-friendly client
// via WithHTTPClient if you need long-running streams.
func (e *ExecutorClient) StreamMessage(
	ctx context.Context,
	agentID string,
	params MessageSendParams,
	handler func(StreamEvent) error,
) error {
	if handler == nil {
		return fmt.Errorf("agentx: handler is required")
	}
	req := JSONRPCRequest{
		JSONRPC: "2.0",
		Method:  MethodMessageSend,
		Params:  params,
		ID:      agentID,
	}

	resp, err := e.c.sendRequest(ctx, e.c.executorURL, http.MethodPost, e.path("execute"), nil, req, "text/event-stream")
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		body, _ := io.ReadAll(resp.Body)
		return parseRequestError(resp.StatusCode, body)
	}

	reader := bufio.NewReader(resp.Body)
	var dataBuf bytes.Buffer
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			if err == io.EOF {
				if dataBuf.Len() > 0 {
					if cbErr := handler(StreamEvent{Data: bytes.TrimRight(dataBuf.Bytes(), "\n")}); cbErr != nil {
						return cbErr
					}
				}
				return nil
			}
			return fmt.Errorf("agentx: read stream: %w", err)
		}

		// Blank line marks end of event.
		if line == "\n" || line == "\r\n" {
			if dataBuf.Len() == 0 {
				continue
			}
			ev := StreamEvent{Data: bytes.TrimRight(dataBuf.Bytes(), "\n")}
			dataBuf.Reset()
			if cbErr := handler(ev); cbErr != nil {
				return cbErr
			}
			continue
		}

		// Ignore SSE comments and non-data fields (event:, id:, retry:).
		if strings.HasPrefix(line, "data:") {
			value := strings.TrimPrefix(line, "data:")
			value = strings.TrimPrefix(value, " ")
			value = strings.TrimRight(value, "\n")
			value = strings.TrimRight(value, "\r")
			dataBuf.WriteString(value)
			dataBuf.WriteByte('\n')
		}
	}
}
