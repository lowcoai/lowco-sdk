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
        return f"FluxError({self.message!r})"
