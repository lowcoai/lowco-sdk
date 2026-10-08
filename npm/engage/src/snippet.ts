import type { Metadata } from "./types";
import { isWriteKey } from "./utils";

export interface InlineSnippetOptions {
  /**
   * The app's write key (`ewk_…`, recommended) or another API key. With a
   * write key the snippet passes `apiKey` only: the key selects the org and
   * the app.
   */
  apiKey?: string;
  /** Emitted only when `apiKey` is not a write key. */
  orgId?: string;
  /** Emitted, when given, only when `apiKey` is not a write key. */
  appId?: string;
  autoTrack?: boolean;
  eventName?: string;
  eventData?: Metadata;
}

export interface EmbedSnippetOptions extends InlineSnippetOptions {
  scriptSrc?: string;
}

function stringifyObject(value: Record<string, unknown>): string {
  const entries = Object.entries(value).filter(([, entryValue]) => entryValue !== undefined);

  if (entries.length === 0) {
    return "{}";
  }

  return JSON.stringify(Object.fromEntries(entries), null, 2)
    .replace(/"([^"]+)":/g, "$1:")
    .replace(/"/g, '"');
}

export function createInlineSnippet({
  apiKey = "YOUR_API_KEY",
  orgId = "YOUR_ORG_ID",
  appId,
  autoTrack = true,
  eventName = "signup_completed",
  eventData,
}: InlineSnippetOptions = {}): string {
  const config = stringifyObject({
    apiKey,
    ...(isWriteKey(apiKey) ? {} : { orgId, appId }),
    autoTrack,
  });

  const eventCall = eventData
    ? `LowcoAnalytics.track("${eventName}", ${stringifyObject(eventData)});`
    : `LowcoAnalytics.track("${eventName}");`;

  return `<script>
  LowcoAnalytics.init(${config});

  // Example event
  ${eventCall}
</script>`;
}

export function createEmbedSnippet({
  scriptSrc = "https://YOUR_CDN/lowco-analytics.js",
  ...inlineOptions
}: EmbedSnippetOptions = {}): string {
  return `<script src="${scriptSrc}"></script>
${createInlineSnippet(inlineOptions)}`;
}
