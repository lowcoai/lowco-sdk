package engage

import (
	"net/url"
	"strings"
)

// AttributionKeys are the query parameters the browser SDK captures as
// attribution, in its order.
var AttributionKeys = []string{
	"utm_source",
	"utm_medium",
	"utm_campaign",
	"utm_term",
	"utm_content",
	"utm_id",
	"gclid",
	"fbclid",
	"msclkid",
}

// AttributionFromURL extracts the AttributionKeys from a full URL
// ("https://shop.example/?utm_source=x"), a path with a query
// ("/landing?utm_source=x") or a bare query string ("?utm_source=x" or
// "utm_source=x"). Like the browser SDK, anything after "#" is ignored, the
// first value of a repeated key wins and empty values are skipped. Merge the
// result into an event's properties.
func AttributionFromURL(urlOrQuery string) map[string]string {
	out := map[string]string{}
	query, _, _ := strings.Cut(strings.TrimSpace(urlOrQuery), "#")
	if _, after, ok := strings.Cut(query, "?"); ok {
		query = after
	} else if !strings.Contains(query, "=") {
		return out
	}
	// ParseQuery keeps every pair it can decode even when it reports an error.
	values, _ := url.ParseQuery(query)
	for _, key := range AttributionKeys {
		if v := values[key]; len(v) > 0 && v[0] != "" {
			out[key] = v[0]
		}
	}
	return out
}
