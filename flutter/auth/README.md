# lowcoai_auth

Flutter SDK for **lowco** sign-in: OAuth 2.0 Authorization Code + PKCE against the lowco identity service, secure token storage, silent / proactive refresh and a route guard — the app counterpart of the `@lowcoai/auth` React SDK. The login page runs in the system browser session via [`flutter_web_auth_2`](https://pub.dev/packages/flutter_web_auth_2) (`ASWebAuthenticationSession` on iOS/macOS, Auth Tab / Custom Tabs on Android, a popup on web).

```yaml
dependencies:
  lowcoai_auth: ^0.1.0
```

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:lowcoai_auth/lowcoai_auth.dart';

final auth = LowcoAuth(
  domain: 'https://api.lowco.ai/v1/identity',
  loginPageUrl: 'https://login.example.com/login', // your hosted login page
  tenantId: '<tenant-id>',
  clientId: '<client-id>',
  redirectUri: 'com.example.app://callback',
  onTokens: (tokens) => debugPrint('new tokens, valid until ${tokens.expiresAtTime}'),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  auth.initialize(); // restore / refresh the stored session
  runApp(LowcoAuthProvider(auth: auth, child: const MyApp()));
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = LowcoAuthProvider.of(context); // rebuilds on every auth change
    if (auth.isLoading) return const CircularProgressIndicator();
    if (!auth.isAuthenticated) {
      return FilledButton(onPressed: auth.loginWithRedirect, child: const Text('Sign in'));
    }
    return TextButton(onPressed: auth.logout, child: Text('Sign out ${auth.user?.name}'));
  }
}

// Calling your API:
final token = await auth.getAccessTokenSilently(); // refreshed when needed
```

## Options

| Parameter            | Description |
| -------------------- | ----------- |
| `domain`             | Identity service base **including its route prefix**, e.g. `https://api.lowco.ai/v1/identity`. Tokens are exchanged at `<domain>/tenants/<tenantId>/oauth/token`. |
| `loginPageUrl`       | Hosted login page; opened with `tenant_id`, `client_id`, `redirect_uri`, `response_type=code`, `scope`, `state`, `nonce`, `code_challenge`, `code_challenge_method=S256` (its own query parameters are kept). |
| `tenantId`           | Tenant id. |
| `clientId`           | OAuth client id (public client, no secret). |
| `redirectUri`        | Callback URL, e.g. `com.example.app://callback`. It must be registered on the lowco OAuth client **exactly** — the server does an exact string match at authorize and token time. |
| `callbackUrlScheme`  | Scheme the browser session waits for. Default: the scheme of `redirectUri`. |
| `scope`              | Default `openid profile email offline_access` (`offline_access` yields a refresh token). |
| `storage`            | `TokenStorage`; default `SecureTokenStorage` (`flutter_secure_storage`). `InMemoryTokenStorage` = the React SDK's `cacheLocation: "memory"`. |
| `onTokens`           | Called with every fresh `TokenSet` (login and refresh; not on restore). |
| `onRedirectCallback` | Called with the `appState` given to `loginWithRedirect` after a successful login. |
| `authenticator`      | `(Uri authorizeUrl, String callbackUrlScheme) => Future<String>`; default `FlutterWebAuth2.authenticate`. Wrap it to pass options, e.g. `FlutterWebAuth2Options(preferEphemeral: true)` for a login session that shares no cookies with the browser. |
| `httpClient`         | Your own `http.Client` (not closed by `dispose`). |

## API

| Member                                         | Description |
| ---------------------------------------------- | ----------- |
| `isLoading`, `isAuthenticated`, `error`, `user`, `tokens` | State; `LowcoAuth` is a `ChangeNotifier`. `isAuthenticated` is true while the access token is valid **or** a refresh token can recover it. |
| `initialize()`                                 | Restores the tokens from `lowco:tokens:<tenantId>:<clientId>`: a valid token is used (and refreshed 60 s before expiry), an expired one with a refresh token is refreshed, anything else is cleared. Idempotent. |
| `loginWithRedirect({appState, scope})`         | Runs the PKCE flow. Never throws: a failure clears the session and sets `error` (`LowcoAuthException` with `message`, `code`, `statusCode`, `cause`); a user cancel leaves everything unchanged with `error == null`. |
| `getAccessTokenSilently()`                     | A valid access token, refreshing it first when needed (concurrent calls share one refresh). Throws `LowcoAuthException('Not authenticated.')` or `('Session expired.')`, like the React SDK. |
| `logout()`                                     | Clears storage and state and cancels the refresh timer (local sign-out; tokens are not revoked). |
| `dispose()`                                    | Cancels the refresh timer. |

### Widgets

- `LowcoAuthProvider(auth: auth, child: ...)` — an `InheritedNotifier`; `LowcoAuthProvider.of(context)` / `maybeOf(context)` return the `LowcoAuth` and rebuild the caller on changes (the React `useLowcoAuth()`).
- `WithAuthenticationRequired(child: ..., placeholder: ..., autoLogin: true)` — shows `placeholder` while loading or signed out; once loading has finished and the user is signed out it starts `loginWithRedirect()` **once**. If the user cancels, the placeholder stays (put a "Sign in" button in it); after a later sign-out it starts the login again.

### Stored tokens

`TokenSet.toJson()` is exactly what the React SDK stores:

```json
{ "access_token": "…", "refresh_token": "…", "id_token": "…", "expires_at": 1790000000000, "scope": "openid profile email offline_access" }
```

`expires_at` is epoch **milliseconds**. Refreshes merge over the previous set (a missing `refresh_token` / `id_token` / `scope` in the response keeps the old value).

`user` is a `UserProfile` (`sub`, `email`, `name`, `picture`, `claims`, `user['any_claim']`) decoded from the `id_token` (else the `access_token`) payload **without verifying the signature** — use it for display only and let your API validate the access token.

### Differences from the React SDK

- A rejected refresh (at startup, in the background or in `getAccessTokenSilently`) **never opens the login page by itself**: the session is cleared and listeners are notified, so the UI (or `WithAuthenticationRequired`) decides when to sign in again.
- A refresh that fails without a verdict from the server (offline, timeout, 5xx) keeps the session so an app started offline stays signed in; `getAccessTokenSilently` then throws `LowcoAuthException('Refresh token exchange failed.')` and retries on the next call.
- The OAuth transaction (state, verifier) lives in memory for the duration of the browser session; there is no `handleRedirectCallback`.

## Platform setup

**Redirect URI.** Register the exact `redirectUri` on your lowco OAuth client. Custom schemes must be valid RFC 3986 schemes (lowercase letters, digits, `+`, `-`, `.`; no `_`), e.g. `com.example.app://callback`.

**Android** — add `flutter_web_auth_2`'s callback activity to `android/app/src/main/AndroidManifest.xml`, with your callback scheme:

```xml
<activity
  android:name="com.linusu.flutter_web_auth_2.CallbackActivity"
  android:exported="true"
  android:taskAffinity="">
  <intent-filter android:label="flutter_web_auth_2">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="com.example.app" />
  </intent-filter>
</activity>
```

`flutter_web_auth_2` also recommends `android:taskAffinity=""` on your `MainActivity`. With an `https` redirect (App Links) pass `FlutterWebAuth2Options(httpsHost: ..., httpsPath: ...)` through a custom `authenticator`.

**iOS / macOS** — nothing extra for a custom scheme (`ASWebAuthenticationSession` captures it). macOS sandboxed apps need the `com.apple.security.network.client` entitlement for the token request. For an `https` (Universal Link) callback, pass `httpsHost` / `httpsPath` options as above.

**Web** — the login page opens in a popup and the redirect must land on a page of your app that posts the URL back. Create `web/auth.html`:

```html
<!DOCTYPE html>
<title>Authentication complete</title>
<p>Authentication is complete. If this does not happen automatically, please close the window.</p>
<script>
  const message = { 'flutter-web-auth-2': window.location.href };
  if (window.opener) {
    window.opener.postMessage(message, window.location.origin);
    window.close();
  } else if (window.parent && window.parent !== window) {
    window.parent.postMessage(message, window.location.origin);
  } else {
    localStorage.setItem('flutter-web-auth-2', window.location.href);
    window.close();
  }
</script>
```

and use `redirectUri: 'https://your.app/auth.html'` (same origin as the app, registered on the client). Tokens are then kept in browser storage by `flutter_secure_storage`'s web implementation.

**Windows / Linux** — `flutter_web_auth_2` uses a webview by default (see its `desktop_webview_window` setup), or `FlutterWebAuth2Options(useWebview: false)` with an `http://localhost:<port>` redirect URI.

## Testing

Inject everything so no platform channel is touched:

```dart
final auth = LowcoAuth(
  ...,
  storage: InMemoryTokenStorage(),
  httpClient: MockClient((req) async => http.Response(jsonEncode({...}), 200)),
  authenticator: (url, scheme) async =>
      'com.example.app://callback?code=abc&state=${url.queryParameters['state']}',
)..now = () => fixedTime; // @visibleForTesting clock
```
