/** Prefix of an engage app write key (`ewk_` + 32 hex characters). */
export const WRITE_KEY_PREFIX = "ewk_";

/**
 * Whether `apiKey` is an engage app write key. A write key selects the org and
 * the app server-side; any other key (user JWT, platform API key) relies on
 * the `X-Org-Id` / `X-Engage-App-Id` headers.
 */
export const isWriteKey = (apiKey: string | null | undefined): boolean =>
  typeof apiKey === "string" && apiKey.startsWith(WRITE_KEY_PREFIX);

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
