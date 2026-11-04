/** Header carrying an `lc_` API key; other tokens travel as `Authorization: Bearer`. */
export const HEADER_API_KEY = "X-Api-Key";

/** Header carrying the organization id. */
export const HEADER_ORG_ID = "X-Org-Id";

/** Header selecting the engage app; absent means the org's default app. */
export const HEADER_ENGAGE_APP_ID = "X-Engage-App-Id";

/** Whether `apiKey` is a Lowco API key (`lc_…`) rather than an access token. */
export const isApiKey = (apiKey: string): boolean =>
  apiKey.trim().startsWith("lc_");

export const generateId = () => {
  const uuid =
    Math.random().toString(36).substring(2, 15) +
    Math.random().toString(36).substring(2, 15);

  if (
    typeof window === "undefined" ||
    typeof window.localStorage === "undefined"
  ) {
    return uuid;
  }

  let uuidFromLocalStorage = localStorage.getItem("lowco_uuid");
  if (!uuidFromLocalStorage) {
    uuidFromLocalStorage = uuid;
    localStorage.setItem("lowco_uuid", uuidFromLocalStorage);
  }
  return uuidFromLocalStorage;
};
