import LowcoAnalytics from "./core";

export default LowcoAnalytics;
export { createEmbedSnippet, createInlineSnippet } from "./snippet";
export {
  HEADER_API_KEY,
  HEADER_ENGAGE_APP_ID,
  HEADER_ORG_ID,
  isApiKey,
} from "./utils";
export type {
  Config,
  DeviceInfo,
  Event,
  Identify,
  LocationInfo,
  Metadata,
} from "./types";
export type { EmbedSnippetOptions, InlineSnippetOptions } from "./snippet";
