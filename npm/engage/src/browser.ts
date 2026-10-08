import LowcoAnalytics from "./core";
import { createEmbedSnippet, createInlineSnippet } from "./snippet";

declare global {
  interface Window {
    LowcoAnalytics?: typeof LowcoAnalytics;
  }
}

if (typeof window !== "undefined") {
  window.LowcoAnalytics = LowcoAnalytics;
}

export default LowcoAnalytics;
export { createEmbedSnippet, createInlineSnippet };
