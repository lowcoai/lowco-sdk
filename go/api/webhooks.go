package api

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"time"
)

// SignatureHeader is the signature header on every webhook delivery.
const SignatureHeader = "Lowco-Signature"

// ErrSignature is returned by ConstructEvent when a delivery does not verify.
var ErrSignature = errors.New("lowco api: the Lowco-Signature does not match this body and secret, or its timestamp is too old")

// VerifyOption adjusts VerifySignature.
type VerifyOption func(*verifyOptions)

type verifyOptions struct {
	tolerance time.Duration
	now       time.Time
}

// WithTolerance sets how far the timestamp may be from now (default 5 minutes).
func WithTolerance(d time.Duration) VerifyOption { return func(o *verifyOptions) { o.tolerance = d } }

// WithNow sets the current time (for tests).
func WithNow(t time.Time) VerifyOption { return func(o *verifyOptions) { o.now = t } }

// VerifySignature checks Lowco-Signature: t=<unix seconds>,v1=<hex
// HMAC-SHA256(secret, "<t>.<raw body>")>. Pass the raw request body and the
// endpoint's whsec_… secret as-is. During a secret rotation the header may
// carry several v1 values; any one matching verifies.
func VerifySignature(header string, rawBody []byte, secret string, opts ...VerifyOption) bool {
	o := verifyOptions{tolerance: 5 * time.Minute, now: time.Now()}
	for _, f := range opts {
		f(&o)
	}
	var t int64
	var sigs []string
	for _, piece := range strings.Split(header, ",") {
		k, v, _ := strings.Cut(strings.TrimSpace(piece), "=")
		switch k {
		case "t":
			n, err := strconv.ParseInt(v, 10, 64)
			if err != nil {
				return false
			}
			t = n
		case "v1":
			if v != "" {
				sigs = append(sigs, v)
			}
		}
	}
	if t == 0 || len(sigs) == 0 {
		return false
	}
	if d := o.now.Sub(time.Unix(t, 0)); d > o.tolerance || d < -o.tolerance {
		return false
	}
	m := hmac.New(sha256.New, []byte(secret))
	m.Write([]byte(strconv.FormatInt(t, 10) + "."))
	m.Write(rawBody)
	want := hex.EncodeToString(m.Sum(nil))
	for _, s := range sigs {
		if hmac.Equal([]byte(s), []byte(want)) {
			return true
		}
	}
	return false
}

// WebhookEvent is one delivery's event.
type WebhookEvent struct {
	ID          string          `json:"id"`
	Type        string          `json:"type"`
	CreatedAt   string          `json:"created_at"`
	Environment string          `json:"environment"`
	Data        json.RawMessage `json:"data"`
}

// ConstructEvent verifies a delivery and decodes its event.
func ConstructEvent(rawBody []byte, header, secret string, opts ...VerifyOption) (*WebhookEvent, error) {
	if !VerifySignature(header, rawBody, secret, opts...) {
		return nil, ErrSignature
	}
	var e WebhookEvent
	if err := json.Unmarshal(rawBody, &e); err != nil {
		return nil, err
	}
	return &e, nil
}
