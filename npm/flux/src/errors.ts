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

/**
 * Emitted through `onError` when the server rejects the connection's token.
 * The client then stops reconnecting until a different token is available
 * (`setToken`, or `getToken` returning a new one) or `connect()` is called.
 */
export class FluxUnauthorizedError extends FluxError {
  constructor() {
    super("flux rejected the token; reconnecting stops until it changes");
    this.name = "FluxUnauthorizedError";
  }
}
