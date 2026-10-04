from __future__ import annotations


class FluxError(Exception):
    """Raised when the flux client cannot operate: invalid input (a blank
    token, org id, topic or event name) or ``send_message`` while the socket
    is not open.

    Transient socket problems (dial failures, parse failures, pong mismatch,
    abnormal closures) are not raised; they are reported to ``on_error``
    handlers and the client reconnects on its own.
    """

    def __init__(self, message: str) -> None:
        self.message = message
        super().__init__(message)

    def __repr__(self) -> str:
        return f"{type(self).__name__}({self.message!r})"


class FluxUnauthorizedError(FluxError):
    """Reported to ``on_error`` handlers (never raised) when the server
    rejects the token: it opens the socket, then sends an ``Unauthorized``
    error frame on ``flux:error`` and/or closes it with code 1008.

    The client then reconnects only with a different token, from
    ``token_provider`` or ``set_token()``; a token the server has just
    rejected is not retried on a timer.
    """

    def __init__(self, message: str = "the server rejected the token (unauthorized)") -> None:
        super().__init__(message)
