# lowcoai-auth

Framework-agnostic Python helpers for the **lowco** OAuth 2.0 Authorization Code + PKCE flow: the server-side counterpart of the React SDK [`@lowcoai/auth`](../../npm/auth), with the same wire behaviour and the same persisted token shape. Works with Flask, Django, FastAPI, Starlette, CLIs with a loopback redirect, and so on. Sync and asyncio clients with the same surface, built on [httpx](https://www.python-httpx.org/). Python 3.10+.

```bash
pip install lowcoai-auth
```

## Quick start (Flask)

```python
from flask import Flask, redirect, request, session
from lowcoai.auth import AuthorizationRequest, LowcoAuthClient, LowcoAuthError, get_user

app = Flask(__name__)
app.secret_key = "..."

auth = LowcoAuthClient(
    "https://api.lowco.ai/v1/identity",  # domain
    "https://auth.lowco.ai/login",  # login_page_url
    "tenant_123",
    "client_abc",
    redirect_uri="https://app.example.com/auth/callback",
)


@app.get("/login")
def login():
    req = auth.create_authorization_request(app_state={"returnTo": request.args.get("next", "/")})
    session["lowco_auth"] = req.to_dict()  # holds the PKCE verifier until the callback
    return redirect(req.url)


@app.get("/auth/callback")
def callback():
    req = AuthorizationRequest.from_dict(session.pop("lowco_auth"))
    try:
        session["tokens"] = auth.handle_redirect_callback(request.url, req)
    except LowcoAuthError as err:
        return f"Sign-in failed: {err.message}", 400
    return redirect((req.app_state or {}).get("returnTo", "/"))


@app.get("/me")
def me():
    try:
        tokens = auth.get_valid_tokens(session.get("tokens"))  # refreshes when needed
    except LowcoAuthError:
        return redirect("/login")
    session["tokens"] = tokens
    return {"user": get_user(tokens), "access_token_expires_at": tokens["expires_at"]}
```

### asyncio

```python
from lowcoai.auth import AsyncLowcoAuthClient

async with AsyncLowcoAuthClient(
    domain, login_page_url, tenant_id, client_id, redirect_uri=redirect_uri
) as auth:
    req = auth.create_authorization_request()  # sync: no I/O
    tokens = await auth.handle_redirect_callback(callback_url, req)
    tokens = await auth.get_valid_tokens(tokens)
```

`AsyncLowcoAuthClient` has the same methods as `LowcoAuthClient`; the network methods are coroutines and `create_authorization_request` stays synchronous. Close it with `await auth.aclose()` if you don't use `async with`.

### CLI with a loopback redirect

```python
req = auth.create_authorization_request(redirect_uri="http://127.0.0.1:8765/callback")
webbrowser.open(req.url)
callback_path = wait_for_one_request_on_port(8765)  # e.g. "/callback?code=...&state=..."
tokens = auth.handle_redirect_callback(callback_path, req)
```

## Options

| Argument         | Description                                                                               |
| ---------------- | ----------------------------------------------------------------------------------------- |
| `domain`         | Auth server base, e.g. `https://api.lowco.ai/v1/identity`. Token endpoint: `{domain}/tenants/{tenant_id}/oauth/token`. |
| `login_page_url` | Hosted login page the user is sent to. A query string already on it is kept.             |
| `tenant_id`      | Tenant identifier.                                                                        |
| `client_id`      | OAuth client identifier (public client: no secret is sent, PKCE protects the code).      |
| `redirect_uri`   | Default callback URL. Required here or per `create_authorization_request` call.          |
| `scope`          | Default scope, `"openid profile email offline_access"`.                                   |
| `timeout`        | Per-request timeout in seconds (default `30`). `None` disables it.                        |
| `http_client`    | Your own `httpx.Client` / `httpx.AsyncClient` (proxies, retries, test transports). It is not closed by the SDK. |

The client stores nothing per user, so one instance can be shared by the whole app. `auth.token_endpoint` returns the token URL.

## Surface

| Call | What it does |
| ---- | ------------ |
| `create_authorization_request(*, redirect_uri=None, scope=None, app_state=None)` | Generates `state`, `nonce` (24 random bytes each) and a PKCE `code_verifier` (48 bytes), all base64url without padding, and returns an `AuthorizationRequest` whose `url` is `login_page_url` plus `tenant_id`, `client_id`, `redirect_uri`, `response_type=code`, `scope`, `state`, `nonce`, `code_challenge` (S256) and `code_challenge_method=S256`. No I/O. |
| `handle_redirect_callback(callback_url, request)` | Reads `code` / `state` (full URL, `/path?query` or bare query), raises `LowcoAuthError` on an OAuth `error`, a missing `code` / `state` or a `state` mismatch (constant-time compare), then calls `exchange_code`. |
| `exchange_code(code, request)` | `POST` form `grant_type=authorization_code`, `tenant_id`, `client_id`, `code`, `code_verifier`, `redirect_uri`. Returns a `TokenSet`. |
| `refresh_tokens(tokens_or_refresh_token)` | `POST` form `grant_type=refresh_token`, `tenant_id`, `client_id`, `refresh_token`. Given a `TokenSet`, the response is merged over it (a refresh token the server does not rotate is kept). |
| `get_valid_tokens(tokens)` | Returns `tokens` unchanged (same object) while the access token is valid, refreshes when there is a refresh token, else raises `LowcoAuthError("Session expired.")` (`"Not authenticated."` without tokens). |

Module-level helpers:

| Helper | Description |
| ------ | ----------- |
| `is_access_token_valid(tokens, skew_seconds=60)` | `expires_at` is more than `skew_seconds` in the future. |
| `can_recover_session(tokens)` | Access token still valid, or a refresh token is present. |
| `get_user(tokens)` | Claims of the ID token (else the access token) as a `UserProfile`: `sub`, `email`, `name`, `picture` plus every other claim. |

> **`get_user` does not verify the JWT signature.** Use it for display only (showing the user's name, avatar, email). For authorisation decisions, validate the access token on the server that receives it.

## Data shapes

`TokenSet` is the dict the React SDK persists (under `lowco:tokens:<tenantId>:<clientId>`), so the two can share stored sessions:

```python
{
    "access_token": "…",  # required
    "refresh_token": "…",
    "id_token": "…",
    "expires_at": 1790000000000,  # epoch MILLISECONDS (JavaScript Date.now() units)
    "scope": "openid profile email offline_access",
    "token_type": "Bearer",
    "expires_in": 3600,  # other response fields are kept, like the React SDK
}
```

`expires_at` is `now_ms + expires_in * 1000`, computed when the tokens arrive. Note the unit: compare it with `time.time() * 1000`, not `time.time()`.

`AuthorizationRequest` is a frozen dataclass (`url`, `state`, `nonce`, `code_verifier`, `redirect_uri`, `scope`, `app_state`). `to_dict()` / `AuthorizationRequest.from_dict(...)` turn it into and back from a JSON-serialisable dict, so it can live in a server-side session or an encrypted cookie between the redirect and the callback. `from_dict` needs `state`, `code_verifier` and `redirect_uri` only, so you can drop `url` to save space. `code_verifier` must only travel back to your own server: keep it in the session (server-side, or a signed / encrypted cookie) and never hand it to page scripts or third parties. It is left out of `repr()`.

## Errors

Flow failures raise `LowcoAuthError` with `message`, `status_code`, `code` and `body`:

| Situation | `message` | Other fields |
| --------- | --------- | ------------ |
| Token endpoint non-2xx (code grant) | `Authorization code exchange failed.` | `status_code`, `body`, `code` = the response's `error` (e.g. `"invalid_grant"`) |
| Token endpoint non-2xx (refresh) | `Refresh token exchange failed.` | same |
| 2xx without a usable `access_token` | `… The token response has no access_token.` | `status_code`, `body` |
| Callback with `?error=…` | `error_description`, or `Authorization failed (<error>).` | `code` = `error` |
| Callback without `code` / `state` | `Missing code or state in the OAuth callback URL.` | |
| Callback `state` differs from the request's | `OAuth state mismatch.` | |
| `get_valid_tokens` without tokens / expired without refresh token | `Not authenticated.` / `Session expired.` | |
| `refresh_tokens` with a `TokenSet` lacking `refresh_token` | `No refresh token available.` | |

`ValueError` is raised for missing constructor arguments, a missing `redirect_uri`, or a blank `code` / refresh token string. Network failures and timeouts surface as `httpx` exceptions.

## Not included

Logout in the React SDK only clears local storage and navigates away; there is no server call to port. Delete the stored `TokenSet` from your session to log a user out.
