import React, {
  ComponentType,
  PropsWithChildren,
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";

export type AuthorizationParams = {
  redirect_uri?: string;
  scope?: string;
  response_type?: "code";
};

export type AppState = {
  returnTo?: string;
  [key: string]: unknown;
};

export type LoginWithRedirectOptions = {
  appState?: AppState;
  authorizationParams?: AuthorizationParams;
};

export type LogoutOptions = {
  returnTo?: string;
};

export type UserProfile = {
  sub?: string;
  email?: string;
  name?: string;
  picture?: string;
  [key: string]: unknown;
};

export type LowcoAuthProviderProps = PropsWithChildren<{
  domain: string;
  loginPageUrl: string;
  tenantId: string;
  clientId: string;
  authorizationParams?: AuthorizationParams;
  cacheLocation?: "memory" | "localstorage";
  onRedirectCallback?: (appState?: AppState) => void;
  onTokens: (tokens: TokenSet) => void;
}>;

export type LowcoAuthContextValue = {
  error: Error | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  user: UserProfile | null;
  loginWithRedirect: (options?: LoginWithRedirectOptions) => Promise<void>;
  logout: (options?: LogoutOptions) => void;
  getAccessTokenSilently: () => Promise<string>;
  handleRedirectCallback: () => Promise<void>;
};

export type TokenSet = {
  access_token: string;
  refresh_token?: string;
  id_token?: string;
  expires_at: number;
  scope?: string;
};

type Transaction = {
  state: string;
  nonce: string;
  codeVerifier: string;
  redirectUri: string;
  scope: string;
  appState?: AppState;
};

/** How long before expiry we treat the access token as "still valid" (proactive refresh). */
const TOKEN_REFRESH_SKEW_MS = 60_000;

function isAccessTokenValid(tokens: TokenSet, skewMs = TOKEN_REFRESH_SKEW_MS) {
  return tokens.expires_at > Date.now() + skewMs;
}

/**
 * True when the user has an access token and the session is still usable
 * (non-expired access token, or a refresh token to recover).
 */
function canRecoverSession(tokens: TokenSet | null) {
  if (!tokens?.access_token) {
    return false;
  }
  return isAccessTokenValid(tokens) || Boolean(tokens.refresh_token);
}

const context = createContext<LowcoAuthContextValue | null>(null);
const memoryStore = new Map<string, string>();

export function LowcoAuthProvider({
  children,
  domain,
  loginPageUrl,
  tenantId,
  clientId,
  authorizationParams,
  cacheLocation = "localstorage",
  onRedirectCallback,
  onTokens,
}: LowcoAuthProviderProps) {
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const [tokens, setTokens] = useState<TokenSet | null>(null);
  const [user, setUser] = useState<UserProfile | null>(null);
  const callbackHandled = useRef(false);
  const refreshTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const storage = getStorage(cacheLocation);
  const transactionStorage = getTransactionStorage();
  const cacheKey = `lowco:tokens:${tenantId}:${clientId}`;

  function scheduleTokenRefresh(tokenSet: TokenSet) {
    if (refreshTimerRef.current) {
      clearTimeout(refreshTimerRef.current);
      refreshTimerRef.current = null;
    }
    if (!tokenSet.refresh_token) return;
    const delay = tokenSet.expires_at - Date.now() - TOKEN_REFRESH_SKEW_MS;
    if (delay <= 0) return;
    refreshTimerRef.current = setTimeout(() => {
      void (async () => {
        try {
          const refreshed = await refreshTokens({
            domain,
            tenantId,
            clientId,
            refreshToken: tokenSet.refresh_token!,
          });
          const nextTokens: TokenSet = {
            ...tokenSet,
            ...refreshed,
            expires_at: Date.now() + refreshed.expires_in * 1000,
          };
          persistTokens(cacheKey, storage, nextTokens);
          setTokens(nextTokens);
          onTokens(nextTokens);
          setUser(extractUser(nextTokens));
          scheduleTokenRefresh(nextTokens);
        } catch {
          sessionExpiredRedirect();
        }
      })();
    }, delay);
  }

  function sessionExpiredRedirect() {
    clearTokens(cacheKey, storage);
    setTokens(null);
    setUser(null);
    setError(null);
    if (typeof window !== "undefined") {
      void loginWithRedirect({
        appState: { returnTo: window.location.href },
      });
    }
  }

  useEffect(() => {
    if (typeof window === "undefined") {
      return;
    }

    const url = new URL(window.location.href);
    if (url.searchParams.get("code") && url.searchParams.get("state")) {
      if (callbackHandled.current) {
        return;
      }
      callbackHandled.current = true;
      void handleRedirectCallbackInternal();
      return;
    }

    void (async () => {
      const existing = storage.get(cacheKey);
      if (!existing) {
        setIsLoading(false);
        return;
      }
      const parsed = JSON.parse(existing) as TokenSet;

      if (!canRecoverSession(parsed)) {
        clearTokens(cacheKey, storage);
        setTokens(null);
        setUser(null);
        setIsLoading(false);
        return;
      }

      if (isAccessTokenValid(parsed)) {
        setTokens(parsed);
        setUser(extractUser(parsed));
        scheduleTokenRefresh(parsed);
        setIsLoading(false);
        return;
      }

      if (!parsed.refresh_token) {
        clearTokens(cacheKey, storage);
        setTokens(null);
        setUser(null);
        setIsLoading(false);
        return;
      }

      setIsLoading(true);
      try {
        const refreshed = await refreshTokens({
          domain,
          tenantId,
          clientId,
          refreshToken: parsed.refresh_token,
        });
        const nextTokens: TokenSet = {
          ...parsed,
          ...refreshed,
          expires_at: Date.now() + refreshed.expires_in * 1000,
        };
        persistTokens(cacheKey, storage, nextTokens);
        setTokens(nextTokens);
        onTokens(nextTokens);
        setUser(extractUser(nextTokens));
        scheduleTokenRefresh(nextTokens);
      } catch {
        clearTokens(cacheKey, storage);
        setTokens(null);
        setUser(null);
        sessionExpiredRedirect();
      } finally {
        setIsLoading(false);
      }
    })();
  }, []);

  useEffect(() => {
    return () => {
      if (refreshTimerRef.current) {
        clearTimeout(refreshTimerRef.current);
      }
    };
  }, []);

  async function loginWithRedirect(options?: LoginWithRedirectOptions) {
    const redirectUri =
      options?.authorizationParams?.redirect_uri ??
      authorizationParams?.redirect_uri ??
      `${window.location.origin}/auth/callback`;
    const scope =
      options?.authorizationParams?.scope ??
      authorizationParams?.scope ??
      "openid profile email offline_access";
    const responseType = options?.authorizationParams?.response_type ?? "code";

    const state = randomString(24);
    const nonce = randomString(24);
    const codeVerifier = randomString(48);
    const codeChallenge = await pkceChallenge(codeVerifier);
    const transaction: Transaction = {
      state,
      nonce,
      codeVerifier,
      redirectUri,
      scope,
      appState: options?.appState ?? {
        returnTo: window.location.href,
      },
    };

    transactionStorage.set(transactionKey(state), JSON.stringify(transaction));

    const url = new URL(loginPageUrl);
    url.searchParams.set("tenant_id", tenantId);
    url.searchParams.set("client_id", clientId);
    url.searchParams.set("redirect_uri", redirectUri);
    url.searchParams.set("response_type", responseType);
    url.searchParams.set("scope", scope);
    url.searchParams.set("state", state);
    url.searchParams.set("nonce", nonce);
    url.searchParams.set("code_challenge", codeChallenge);
    url.searchParams.set("code_challenge_method", "S256");

    window.location.assign(url.toString());
  }

  async function handleRedirectCallback() {
    await handleRedirectCallbackInternal();
  }

  async function handleRedirectCallbackInternal() {
    setIsLoading(true);
    setError(null);

    try {
      const url = new URL(window.location.href);
      const code = url.searchParams.get("code");
      const state = url.searchParams.get("state");
      if (!code || !state) {
        setIsLoading(false);
        return;
      }

      const rawTransaction = transactionStorage.get(transactionKey(state));
      if (!rawTransaction) {
        throw new Error("Missing OAuth transaction state.");
      }
      transactionStorage.delete(transactionKey(state));

      const transaction = JSON.parse(rawTransaction) as Transaction;
      const tokenResponse = await exchangeCode({
        domain,
        tenantId,
        clientId,
        code,
        codeVerifier: transaction.codeVerifier,
        redirectUri: transaction.redirectUri,
      });

      const nextTokens: TokenSet = {
        ...tokenResponse,
        expires_at: Date.now() + tokenResponse.expires_in * 1000,
      };
      persistTokens(cacheKey, storage, nextTokens);
      setTokens(nextTokens);
      onTokens(nextTokens);
      setUser(extractUser(nextTokens));
      scheduleTokenRefresh(nextTokens);

      const target = transaction.appState?.returnTo;
      onRedirectCallback?.(transaction.appState);
      if (target) {
        window.history.replaceState({}, document.title, target);
      } else {
        url.searchParams.delete("code");
        url.searchParams.delete("state");
        window.history.replaceState({}, document.title, url.pathname);
      }
    } catch (cause) {
      setError(
        cause instanceof Error ? cause : new Error("Authentication failed."),
      );
      clearTokens(cacheKey, storage);
      setTokens(null);
      setUser(null);
    } finally {
      setIsLoading(false);
    }
  }

  async function getAccessTokenSilently() {
    const current = tokens ?? readTokens(cacheKey, storage);
    if (!current) {
      throw new Error("Not authenticated.");
    }

    if (isAccessTokenValid(current)) {
      return current.access_token;
    }
    if (!current.refresh_token) {
      sessionExpiredRedirect();
      throw new Error("Session expired.");
    }

    try {
      const refreshed = await refreshTokens({
        domain,
        tenantId,
        clientId,
        refreshToken: current.refresh_token,
      });
      const nextTokens: TokenSet = {
        ...current,
        ...refreshed,
        expires_at: Date.now() + refreshed.expires_in * 1000,
      };
      persistTokens(cacheKey, storage, nextTokens);
      setTokens(nextTokens);
      onTokens(nextTokens);
      setUser(extractUser(nextTokens));
      scheduleTokenRefresh(nextTokens);
      return nextTokens.access_token;
    } catch {
      sessionExpiredRedirect();
      throw new Error("Session expired.");
    }
  }

  function logout(options?: LogoutOptions) {
    if (refreshTimerRef.current) {
      clearTimeout(refreshTimerRef.current);
      refreshTimerRef.current = null;
    }
    clearTokens(cacheKey, storage);
    setTokens(null);
    setUser(null);
    setError(null);
    if (options?.returnTo) {
      window.location.assign(options.returnTo);
    }
  }

  const value: LowcoAuthContextValue = {
    error,
    isAuthenticated: canRecoverSession(tokens),
    isLoading,
    user,
    loginWithRedirect,
    logout,
    getAccessTokenSilently,
    handleRedirectCallback,
  };

  return <context.Provider value={value}>{children}</context.Provider>;
}

export function useLowcoAuth() {
  const value = useContext(context);
  if (!value) {
    throw new Error("useLowcoAuth must be used inside LowcoAuthProvider.");
  }
  return value;
}

export function withAuthenticationRequired<P extends object>(
  Component: ComponentType<P>,
) {
  return function ProtectedComponent(props: P) {
    const { isAuthenticated, isLoading, loginWithRedirect } = useLowcoAuth();

    useEffect(() => {
      if (!isLoading && !isAuthenticated) {
        void loginWithRedirect();
      }
    }, [isAuthenticated, isLoading]);

    if (!isAuthenticated) {
      return null;
    }

    return <Component {...props} />;
  };
}

function getStorage(cacheLocation: "memory" | "localstorage") {
  if (typeof window === "undefined" || cacheLocation === "memory") {
    return {
      get(key: string) {
        return memoryStore.get(key) ?? null;
      },
      set(key: string, value: string) {
        memoryStore.set(key, value);
      },
      delete(key: string) {
        memoryStore.delete(key);
      },
    };
  }
  return {
    get(key: string) {
      return window.localStorage.getItem(key);
    },
    set(key: string, value: string) {
      window.localStorage.setItem(key, value);
    },
    delete(key: string) {
      window.localStorage.removeItem(key);
    },
  };
}

function getTransactionStorage() {
  if (typeof window === "undefined") {
    return {
      get(_key: string) {
        return null;
      },
      set(_key: string, _value: string) {},
      delete(_key: string) {},
    };
  }
  return {
    get(key: string) {
      return window.sessionStorage.getItem(key);
    },
    set(key: string, value: string) {
      window.sessionStorage.setItem(key, value);
    },
    delete(key: string) {
      window.sessionStorage.removeItem(key);
    },
  };
}

function transactionKey(state: string) {
  return `lowco:transaction:${state}`;
}

async function pkceChallenge(verifier: string) {
  const buffer = new TextEncoder().encode(verifier);
  const digest = await window.crypto.subtle.digest("SHA-256", buffer);
  return base64UrlEncode(new Uint8Array(digest));
}

function randomString(size: number) {
  const bytes = new Uint8Array(size);
  window.crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

function base64UrlEncode(input: Uint8Array) {
  let raw = "";
  input.forEach((value) => {
    raw += String.fromCharCode(value);
  });
  return window
    .btoa(raw)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function extractUser(tokens: TokenSet): UserProfile | null {
  const payload = decodeJWT<Record<string, unknown>>(
    tokens.id_token ?? tokens.access_token,
  );
  if (!payload) {
    return null;
  }
  return {
    sub: stringValue(payload.sub),
    email: stringValue(payload.email),
    name: stringValue(payload.name),
    picture: stringValue(payload.picture),
    ...payload,
  };
}

function decodeJWT<T>(raw?: string): T | null {
  if (!raw) {
    return null;
  }
  const segments = raw.split(".");
  const payload = segments[1];
  if (!payload) {
    return null;
  }
  const base64 = payload.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
  const json = window.atob(padded);
  return JSON.parse(json) as T;
}

function stringValue(value: unknown) {
  return typeof value === "string" ? value : undefined;
}

function persistTokens(
  key: string,
  storage: ReturnType<typeof getStorage>,
  tokens: TokenSet,
) {
  storage.set(key, JSON.stringify(tokens));
}

function readTokens(key: string, storage: ReturnType<typeof getStorage>) {
  const raw = storage.get(key);
  if (!raw) {
    return null;
  }
  return JSON.parse(raw) as TokenSet;
}

function clearTokens(key: string, storage: ReturnType<typeof getStorage>) {
  storage.delete(key);
}

async function exchangeCode({
  domain,
  tenantId,
  clientId,
  code,
  codeVerifier,
  redirectUri,
}: {
  domain: string;
  tenantId: string;
  clientId: string;
  code: string;
  codeVerifier: string;
  redirectUri: string;
}) {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    tenant_id: tenantId,
    client_id: clientId,
    code,
    code_verifier: codeVerifier,
    redirect_uri: redirectUri,
  });

  const response = await fetch(
    `${trimSlash(domain)}/tenants/${tenantId}/oauth/token`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body,
    },
  );
  if (!response.ok) {
    throw new Error("Authorization code exchange failed.");
  }
  return response.json() as Promise<{
    access_token: string;
    refresh_token?: string;
    id_token?: string;
    expires_in: number;
    scope?: string;
  }>;
}

async function refreshTokens({
  domain,
  tenantId,
  clientId,
  refreshToken,
}: {
  domain: string;
  tenantId: string;
  clientId: string;
  refreshToken: string;
}) {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    tenant_id: tenantId,
    client_id: clientId,
    refresh_token: refreshToken,
  });
  const response = await fetch(
    `${trimSlash(domain)}/tenants/${tenantId}/oauth/token`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body,
    },
  );
  if (!response.ok) {
    throw new Error("Refresh token exchange failed.");
  }
  return response.json() as Promise<{
    access_token: string;
    refresh_token?: string;
    id_token?: string;
    expires_in: number;
    scope?: string;
  }>;
}

function trimSlash(value: string) {
  return value.replace(/\/+$/g, "");
}
