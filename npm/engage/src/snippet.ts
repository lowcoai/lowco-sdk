import type { Metadata } from "./types";

export interface InlineSnippetOptions {
  apiKey?: string;
  orgId?: string;
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
  autoTrack = true,
  eventName = "signup_completed",
  eventData,
}: InlineSnippetOptions = {}): string {
  const config = stringifyObject({
    apiKey,
    orgId,
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
