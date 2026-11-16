import LowcoAnalytics from "./core";

export default LowcoAnalytics;
export { MAX_BATCH } from "./core";
export { matchPagePattern, pageAllowed } from "./forms";
export { createEmbedSnippet, createInlineSnippet } from "./snippet";
export {
  HEADER_API_KEY,
  HEADER_ENGAGE_APP_ID,
  HEADER_ORG_ID,
  isApiKey,
} from "./utils";
export type {
  BatchEventInput,
  BatchResult,
  BatchRow,
  Config,
  DeviceInfo,
  Event,
  Identify,
  LocationInfo,
  Metadata,
  EngageForm,
  FormConsent,
  FormContent,
  FormDisplay,
  FormField,
  FormFieldError,
  FormFieldType,
  FormMode,
  FormSubmitResult,
  FormTrigger,
  FormTriggerType,
} from "./types";
export type { EmbedSnippetOptions, InlineSnippetOptions } from "./snippet";
export {
  CLICK_ID_KEYS,
  collectAdIds,
  createEventId,
  fbcFromFbclid,
  gaClientIdFromCookie,
  gaSessionId,
  mergeSessionClickIds,
  mirrorEventId,
  parseCookies,
  primaryClickId,
  readClickIds,
} from "./adids";
export type { AdIdsInput, ClickIdKey } from "./adids";
