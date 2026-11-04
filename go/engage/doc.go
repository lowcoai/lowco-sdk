// Package engage is the server-side Go client for the lowco engage
// event-tracking service: the backend counterpart of the browser SDK
// (@lowcoai/engage). Every call sends one event to
// POST https://api.lowco.ai/v1/engage/track.
//
// Construction requires a credential and an org id; the engage app is
// optional:
//
//	client, err := engage.NewClient(engage.Config{
//		APIKey: "lc_…",    // required: an API key, or an OAuth2 access token
//		OrgID:  "org_123", // required
//		AppID:  "app_123", // optional: omit for the org's default app
//	})
//	if err != nil {
//		log.Fatal(err)
//	}
//
//	err = client.Track(ctx, "signup_completed", engage.Metadata{"plan": "pro"},
//		&engage.EventOptions{UserID: "user_123"})
//
// An lc_ API key is sent as the X-Api-Key header, which is where the gateway
// reads API keys from; any other credential (an OAuth2 access token) is sent
// as "Authorization: Bearer <token>". The org id travels as X-Org-Id and the
// app id, when set, as X-Engage-App-Id.
//
// The client is stateless and safe for concurrent use: it remembers no user,
// keeps no session and captures no device or location information, so pass
// them per call through EventOptions. Non-2xx responses surface as *Error.
package engage
