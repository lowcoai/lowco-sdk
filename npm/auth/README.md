# @lowcoai/auth

React provider and hooks for the **lowco** OAuth (Authorization Code + PKCE) flow. Targets React 18 / 19 in any browser environment.

```bash
npm install @lowcoai/auth
```

## Quick start

```tsx
import { LowcoAuthProvider, useLowcoAuth } from "@lowcoai/auth";

function App() {
  return (
    <LowcoAuthProvider
      domain="https://auth.lowco.example"
      loginPageUrl="https://auth.lowco.example/login"
      tenantId="tenant_123"
      clientId="client_abc"
      cacheLocation="localstorage"
      onTokens={(tokens) => console.log("tokens", tokens)}
    >
      <Home />
    </LowcoAuthProvider>
  );
}

function Home() {
  const { isAuthenticated, user, loginWithRedirect, logout } = useLowcoAuth();

  if (!isAuthenticated) {
    return <button onClick={() => loginWithRedirect()}>Sign in</button>;
  }
  return (
    <>
      <p>Hi {user?.name ?? user?.email}</p>
      <button onClick={() => logout({ returnTo: window.location.origin })}>
        Sign out
      </button>
    </>
  );
}
```

## Provider props

| Prop                   | Description                                                              |
| ---------------------- | ------------------------------------------------------------------------ |
| `domain`               | OAuth server origin (used to call `/tenants/:id/oauth/token`).           |
| `loginPageUrl`         | Hosted login page; the provider redirects here with PKCE params.         |
| `tenantId`             | Tenant identifier.                                                       |
| `clientId`             | OAuth client identifier.                                                 |
| `authorizationParams`  | Override `redirect_uri`, `scope`, `response_type`.                       |
| `cacheLocation`        | `"localstorage"` (default) or `"memory"`.                                |
| `onTokens`             | Called whenever a fresh token set is obtained.                           |
| `onRedirectCallback`   | Optional hook fired after the redirect callback resolves.                |

## Hook API — `useLowcoAuth()`

```ts
const {
  isAuthenticated,
  isLoading,
  error,
  user,
  loginWithRedirect, // (options?) => Promise<void>
  logout,            // (options?) => void
  getAccessTokenSilently, // () => Promise<string>
  handleRedirectCallback, // () => Promise<void>
} = useLowcoAuth();
```

## Guarding routes

```tsx
import { withAuthenticationRequired } from "@lowcoai/auth";

const ProtectedPage = withAuthenticationRequired(MyPage);
```

The wrapper triggers `loginWithRedirect()` when the user isn't authenticated and renders `null` until the redirect completes.

## Notes

- Uses `crypto.subtle` for PKCE — requires a secure context (HTTPS or `localhost`).
- Stores tokens under `lowco:tokens:<tenantId>:<clientId>` (localStorage or in-memory).
- The provider auto-refreshes a minute before expiry when a `refresh_token` is present, and falls back to `loginWithRedirect` on refresh failure.
