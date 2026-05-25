import LowcoAnalytics from "./core";
import { createEmbedSnippet, createInlineSnippet } from "./snippet";

declare global {
  interface Window {
    LowcoAnalytics?: typeof LowcoAnalytics;
    __LOWCO_ANALYTICS_DEFAULT_URL__?: string;
  }
}

if (typeof window !== "undefined") {
  const currentScript =
    typeof document !== "undefined"
      ? (document.currentScript as HTMLScriptElement | null)
      : null;

  if (currentScript) {
    const dataApiUrl = currentScript.getAttribute("data-api-url");

    if (dataApiUrl) {
      window.__LOWCO_ANALYTICS_DEFAULT_URL__ = dataApiUrl.replace(/\/$/, "");
    } else if (currentScript.src) {
      window.__LOWCO_ANALYTICS_DEFAULT_URL__ = new URL(
        currentScript.src,
        window.location.href
      ).origin;
    }
  }

  window.LowcoAnalytics = LowcoAnalytics;
}

export default LowcoAnalytics;
export { createEmbedSnippet, createInlineSnippet };
