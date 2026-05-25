/**
 * Thrown when the flux client cannot operate (e.g. send while disconnected,
 * invalid input). Transient socket errors are surfaced via `onError` handlers
 * instead.
 */
export class FluxError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FluxError";
  }
}
