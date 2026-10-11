package lowcodb

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

// RequestError is returned for any non-2xx response from the manager.
// It always carries StatusCode and the raw response Body; Message and Code
// are populated when the manager returned a JSON error envelope.
type RequestError struct {
	StatusCode int
	Message    string
	Code       string
	Body       string
}

func (e *RequestError) Error() string {
	if e.Message != "" {
		return fmt.Sprintf("lowcodb: status=%d %s", e.StatusCode, e.Message)
	}
	return fmt.Sprintf("lowcodb: status=%d", e.StatusCode)
}

// CodeQuotaExceeded is the body code of a 402 from a base's gateway: the organization's
// plan cap for the metered resource is reached.
const CodeQuotaExceeded = "QUOTA_EXCEEDED"

// QuotaExceededError is the typed form of a 402 QUOTA_EXCEEDED answer from the gateway:
// the organization's plan cap for the metered resource is reached. It wraps the
// RequestError (errors.As works for both) and carries the quota plane's body, so a
// caller can explain, wait for the period to end, or offer the upgrade.
type QuotaExceededError struct {
	*RequestError
	// Meter is the metered resource, e.g. "vlbrofrujc_employees_create".
	Meter string
	// Consumed and Included are the period's usage and the plan's allowance.
	Consumed float64
	Included float64
	// HardCap is the ceiling that refused the call; nil when the plan has none.
	HardCap *float64
	// PeriodEnd is when the usage window resets (RFC 3339), when known.
	PeriodEnd string
	// AppKey names the product whose plan applies.
	AppKey string
	// UpgradeAppKey and UpgradePlans say what would lift the cap, when the plane says.
	UpgradeAppKey string
	UpgradePlans  []string
}

func (e *QuotaExceededError) Error() string {
	if e.Meter != "" {
		return fmt.Sprintf("lowcodb: quota exceeded for %s (consumed %.0f of %.0f)", e.Meter, e.Consumed, e.Included)
	}
	return "lowcodb: quota exceeded"
}

func (e *QuotaExceededError) Unwrap() error { return e.RequestError }

// IsQuotaExceeded reports whether err is a 402 QUOTA_EXCEEDED from the gateway.
func IsQuotaExceeded(err error) bool {
	var q *QuotaExceededError
	return errors.As(err, &q)
}

// parseQuotaExceeded reads the 402 body (core/quota.QuotaError) leniently: the keeper
// writes it at the top level, an envelope would nest it under "error".
func parseQuotaExceeded(base *RequestError, body []byte) *QuotaExceededError {
	var raw map[string]any
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil
	}
	fields := raw
	if nested, ok := raw["error"].(map[string]any); ok {
		if _, has := nested["code"]; has {
			fields = nested
		}
	}
	code, _ := fields["code"].(string)
	if !strings.EqualFold(strings.TrimSpace(code), CodeQuotaExceeded) {
		return nil
	}
	q := &QuotaExceededError{RequestError: base}
	q.Code = CodeQuotaExceeded
	if msg, _ := fields["message"].(string); strings.TrimSpace(msg) != "" {
		q.Message = msg
	}
	q.Meter, _ = fields["meter"].(string)
	q.Consumed = toFloat(fields["consumed"])
	q.Included = toFloat(fields["included"])
	if v, ok := fields["hard_cap"]; ok && v != nil {
		cap := toFloat(v)
		q.HardCap = &cap
	}
	q.PeriodEnd, _ = fields["period_end"].(string)
	q.AppKey, _ = fields["app_key"].(string)
	if up, ok := fields["upgrade"].(map[string]any); ok {
		q.UpgradeAppKey, _ = up["app_key"].(string)
		if plans, ok := up["plans"].([]any); ok {
			for _, p := range plans {
				if s, ok := p.(string); ok {
					q.UpgradePlans = append(q.UpgradePlans, s)
				}
			}
		}
	}
	return q
}

func toFloat(v any) float64 {
	switch n := v.(type) {
	case float64:
		return n
	case int64:
		return float64(n)
	case int:
		return float64(n)
	case json.Number:
		f, _ := n.Float64()
		return f
	}
	return 0
}
