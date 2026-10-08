export const WS_URL = "wss://ws.lowco.ai/";

export const generateClientId = (): string => {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return (
    Date.now().toString(36) + Math.random().toString(36).substring(2, 15)
  );
};

export const buildWebSocketUrl = (
  token: string,
  orgId: string,
  clientId: string,
  queryParams?: Record<string, string>,
): string => {
  const url = new URL(WS_URL);

  url.searchParams.set("token", token);
  url.searchParams.set("orgId", orgId);
  url.searchParams.set("cli", clientId);
  if (queryParams) {
    for (const [key, value] of Object.entries(queryParams)) {
      url.searchParams.set(key, value);
    }
  }
  return url.toString();
};

export const normalizeTopic = (value: string | undefined): string =>
  (value ?? "").trim();

export const normalizeTopics = (topics: string[]): string[] => [
  ...new Set(topics.map((t) => normalizeTopic(t)).filter(Boolean)),
];
