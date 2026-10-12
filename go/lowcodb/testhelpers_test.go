package lowcodb

import "net/url"

// withBaseURL points a client at a test server.
func withBaseURL(u *url.URL) Option {
	return func(c *Client) { c.baseURL = u }
}

func parseBase(raw string) (*url.URL, error) { return url.Parse(raw) }
