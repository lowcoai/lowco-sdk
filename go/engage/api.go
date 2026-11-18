package engage

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Paths of the identity APIs. Like the consent and journey calls, they need
// a server credential (an admin API key), not a browser key.
const (
	AliasPath = "/v1/engage/users/alias"
	MergePath = "/v1/engage/users/merge"
)

// MaxBatch is the most events one TrackBatch call takes.
const MaxBatch = 1000

// Alias types: the other names a person goes by in one app.
const (
	// AliasAnonymous is an SDK device / anonymous id: the person's earlier
	// anonymous events become theirs.
	AliasAnonymous = "anonymous"
	AliasEmail     = "email"
	AliasPhone     = "phone"
	// AliasExternal is an id in another system (a CRM lead id, say).
	AliasExternal = "external"
)

// Consent statuses.
const (
	ConsentOptedIn  = "opted_in"
	ConsentOptedOut = "opted_out"
	ConsentPending  = "pending"
)

// Consent channels.
const (
	ConsentEmail    = "email"
	ConsentSMS      = "sms"
	ConsentWhatsApp = "whatsapp"
	ConsentPush     = "push"
	ConsentWebPush  = "webpush"
	ConsentInApp    = "inapp"
	ConsentAll      = "all"
)

// BatchResult answers TrackBatch: how many events were taken and each one's
// outcome by its place in the batch.
type BatchResult struct {
	Accepted int        `json:"accepted"`
	Rejected int        `json:"rejected"`
	Results  []BatchRow `json:"results"`
}

// BatchRow is how one event of a batch was taken.
type BatchRow struct {
	// Index is the event's place in the batch.
	Index     int    `json:"index"`
	EventName string `json:"eventName"`
	OK        bool   `json:"ok"`
	// Error says why the event was refused: no event name, breaking a
	// strict event definition (see Issues), or "couldn't be queued; send it
	// again" (a transient failure worth retrying).
	Error  string       `json:"error,omitempty"`
	Issues []BatchIssue `json:"issues,omitempty"`
}

// BatchIssue is one way an event breaks its strict event definition.
type BatchIssue struct {
	Property string `json:"property"`
	Kind     string `json:"kind"`
	Expected string `json:"expected"`
	Got      string `json:"got"`
}

// RejectedRows returns the rows that were not taken.
func (r *BatchResult) RejectedRows() []BatchRow {
	var out []BatchRow
	for _, row := range r.Results {
		if !row.OK {
			out = append(out, row)
		}
	}
	return out
}

// AliasResult is whether an alias is now the person's.
type AliasResult struct {
	Claimed bool `json:"claimed"`
	// HeldBy is who already has the alias when it isn't this person's (an
	// alias another person holds stays theirs).
	HeldBy string `json:"heldBy,omitempty"`
}

// Profile is a person's profile as Merge returns it.
type Profile struct {
	ID           string     `json:"id"`
	OrgID        string     `json:"orgId"`
	AppID        string     `json:"appId"`
	UserID       string     `json:"userId"`
	UserMetadata Metadata   `json:"userMetadata"`
	Scores       Metadata   `json:"scores,omitempty"`
	CreatedAt    time.Time  `json:"createdAt"`
	UpdatedAt    *time.Time `json:"updatedAt,omitempty"`
	// Raw is the profile JSON as the service sent it, for fields this
	// struct doesn't name.
	Raw json.RawMessage `json:"-"`
}

// ConsentRequest is a consent change for SetConsent.
type ConsentRequest struct {
	// Channel is one of the Consent channel constants (email, sms,
	// whatsapp, push, webpush, inapp, all).
	Channel string `json:"channel"`
	// Status is ConsentOptedIn, ConsentOptedOut or ConsentPending.
	Status string `json:"status"`
	// Source says where the consent came from (form, import, …); the
	// service records "api" when empty.
	Source string `json:"source,omitempty"`
	// Evidence is kept with the change (a form id, the page, an IP).
	Evidence Metadata `json:"evidence,omitempty"`
}

// ConsentResult is a recorded consent change.
type ConsentResult struct {
	Channel  string `json:"channel"`
	Status   string `json:"status"`
	Previous string `json:"previous,omitempty"`
	// Confirmation is "sent" when a double opt-in confirmation was queued,
	// "not_configured" when the channel needs one but none is set up.
	Confirmation string `json:"confirmation,omitempty"`
}

// JourneyParticipant is a person's place in a journey.
type JourneyParticipant struct {
	ID            string     `json:"id"`
	AppID         string     `json:"appId"`
	JourneyID     string     `json:"journeyId"`
	Version       int        `json:"version"`
	UserID        string     `json:"userId"`
	ExecutionID   string     `json:"executionId,omitempty"`
	Status        string     `json:"status"`
	CurrentNodeID string     `json:"currentNodeId,omitempty"`
	EnteredAt     time.Time  `json:"enteredAt"`
	FinishedAt    *time.Time `json:"finishedAt,omitempty"`
	Context       Metadata   `json:"context,omitempty"`
	ExitReason    string     `json:"exitReason,omitempty"`
}

// TrackBatch sends up to MaxBatch events in one request to
// POST /v1/engage/track/batch. Unlike Track, one bad event doesn't fail the
// rest: the result lists each event's outcome by its place. Build events
// with NewEvent. It returns ErrEmptyBatch or ErrBatchTooLarge before sending,
// and *Error for a non-2xx answer (the whole batch was refused).
func (c *Client) TrackBatch(ctx context.Context, events []Event) (*BatchResult, error) {
	if len(events) == 0 {
		return nil, ErrEmptyBatch
	}
	if len(events) > MaxBatch {
		return nil, ErrBatchTooLarge
	}
	body, err := encodeJSON(struct {
		Events []Event `json:"events"`
	}{events})
	if err != nil {
		return nil, fmt.Errorf("engage: encode events: %w", err)
	}
	var out BatchResult
	if _, err := c.call(ctx, http.MethodPost, TrackBatchPath, body, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// Alias records another name for a person in this app: an anonymous id
// (AliasAnonymous: their earlier anonymous events become theirs), an email,
// a phone number or an external id. An alias another person already holds
// stays theirs: Claimed is false and HeldBy names them. Needs a server
// (admin) credential.
func (c *Client) Alias(ctx context.Context, userID, aliasType, aliasValue string) (*AliasResult, error) {
	if strings.TrimSpace(userID) == "" {
		return nil, ErrMissingUserID
	}
	if strings.TrimSpace(aliasType) == "" || strings.TrimSpace(aliasValue) == "" {
		return nil, ErrMissingAlias
	}
	body, err := encodeJSON(map[string]string{"userId": userID, "aliasType": aliasType, "aliasValue": aliasValue})
	if err != nil {
		return nil, err
	}
	var out AliasResult
	if _, err := c.call(ctx, http.MethodPost, AliasPath, body, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// Merge merges mergeUserID's profile into keepUserID's: its traits fill
// the kept profile's blanks, the stricter consent wins on each channel, and
// its aliases, events and history move over; its id becomes an alias. It
// returns the kept profile. A 202 answer (merged, the event store catching
// up) is success too. A missing profile is an *Error with Status 404.
// Needs a server (admin) credential.
func (c *Client) Merge(ctx context.Context, keepUserID, mergeUserID string) (*Profile, error) {
	if strings.TrimSpace(keepUserID) == "" || strings.TrimSpace(mergeUserID) == "" {
		return nil, ErrMissingUserID
	}
	body, err := encodeJSON(map[string]string{"keepUserId": keepUserID, "mergeUserId": mergeUserID})
	if err != nil {
		return nil, err
	}
	var raw json.RawMessage
	if _, err := c.call(ctx, http.MethodPost, MergePath, body, &raw); err != nil {
		return nil, err
	}
	out := &Profile{}
	if len(raw) > 0 && string(raw) != "null" {
		if err := json.Unmarshal(raw, out); err != nil {
			return nil, fmt.Errorf("engage: decode profile: %w", err)
		}
		out.Raw = raw
	}
	return out, nil
}

// SetConsent records a consent change for a person:
// PUT /v1/engage/users/userId/{userID}/consents. Needs a server (admin)
// credential.
func (c *Client) SetConsent(ctx context.Context, userID string, consent ConsentRequest) (*ConsentResult, error) {
	if strings.TrimSpace(userID) == "" {
		return nil, ErrMissingUserID
	}
	if strings.TrimSpace(consent.Channel) == "" || strings.TrimSpace(consent.Status) == "" {
		return nil, ErrMissingConsent
	}
	body, err := encodeJSON(consent)
	if err != nil {
		return nil, fmt.Errorf("engage: encode consent: %w", err)
	}
	var out ConsentResult
	path := "/v1/engage/users/userId/" + url.PathEscape(userID) + "/consents"
	if _, err := c.call(ctx, http.MethodPut, path, body, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// EnterJourney puts a person in a journey (an API entry, under the
// journey's re-entry rule, entry segment and holdout):
// POST /v1/engage/configurations/journeys/{journeyID}/enter. When the person
// is in it already, or may not re-enter yet, it returns an *Error with
// Status 409 (http.StatusConflict). Needs a server (admin) credential.
func (c *Client) EnterJourney(ctx context.Context, journeyID, userID string) (*JourneyParticipant, error) {
	if strings.TrimSpace(journeyID) == "" {
		return nil, ErrMissingJourneyID
	}
	if strings.TrimSpace(userID) == "" {
		return nil, ErrMissingUserID
	}
	body, err := encodeJSON(map[string]string{"userId": userID})
	if err != nil {
		return nil, err
	}
	var out JourneyParticipant
	path := "/v1/engage/configurations/journeys/" + url.PathEscape(journeyID) + "/enter"
	if _, err := c.call(ctx, http.MethodPost, path, body, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// call sends a JSON request to path and decodes the answer's data into out
// (when out is non-nil). Non-2xx answers become *Error; it returns the
// status code.
func (c *Client) call(ctx context.Context, method, path string, body []byte, out any) (int, error) {
	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, reader)
	if err != nil {
		return 0, transportError(err)
	}
	req.Header = c.headers.Clone()
	resp, err := c.http.Do(req)
	if err != nil {
		return 0, transportError(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		raw, err := io.ReadAll(io.LimitReader(resp.Body, maxErrorBody))
		if err != nil {
			return resp.StatusCode, transportError(err)
		}
		return resp.StatusCode, newResponseError(resp.StatusCode, raw)
	}
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return resp.StatusCode, transportError(err)
	}
	if out == nil {
		return resp.StatusCode, nil
	}
	var envelope struct {
		Data json.RawMessage `json:"data"`
	}
	if len(bytes.TrimSpace(raw)) == 0 {
		return resp.StatusCode, nil
	}
	if err := json.Unmarshal(raw, &envelope); err != nil {
		return resp.StatusCode, fmt.Errorf("engage: decode response: %w", err)
	}
	if len(envelope.Data) == 0 || string(envelope.Data) == "null" {
		return resp.StatusCode, nil
	}
	if err := json.Unmarshal(envelope.Data, out); err != nil {
		return resp.StatusCode, fmt.Errorf("engage: decode response: %w", err)
	}
	return resp.StatusCode, nil
}
