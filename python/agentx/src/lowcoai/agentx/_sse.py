"""Incremental Server-Sent Events parser used by ``stream_message``.

Pure (no I/O) so it can be unit-tested with arbitrary chunk boundaries. The
semantics mirror ``streamMessage`` in the TypeScript SDK:

* events are separated by a blank line (``\\n\\n`` or ``\\r\\n\\r\\n``);
* inside an event, lines are split on ``\\r?\\n`` and only ``data:`` lines are
  kept, each with one optional leading whitespace character removed;
* multiple ``data:`` lines are joined with ``"\\n"``;
* events without any ``data:`` line (comments, ``event:``/``id:``/``retry:``
  only, stray blank lines) are skipped;
* whatever is left in the buffer at end-of-stream is parsed as a final event,
  so a trailing event without a terminating blank line is still delivered.

Bytes are decoded as UTF-8 incrementally (a multi-byte character split across
chunks is handled; a leading BOM is dropped; invalid sequences are replaced),
like the ``TextDecoder`` the TS SDK uses.
"""

from __future__ import annotations

import codecs
import re

__all__ = ["SSEParser"]

_LINE_SPLIT = re.compile(r"\r?\n")
_LEADING_WS = re.compile(r"^\s")
# Longest separator ("\r\n\r\n") minus one: a boundary can straddle at most this
# many characters of already-scanned buffer.
_OVERLAP = 3


class SSEParser:
    """Feed raw chunks with :meth:`feed`; call :meth:`finish` at end-of-stream.

    Both return the ``data`` payloads of the events completed so far.
    """

    def __init__(self) -> None:
        self._buf = ""
        self._decoder = codecs.getincrementaldecoder("utf-8-sig")(errors="replace")

    def feed(self, chunk: bytes | str) -> list[str]:
        text = self._decoder.decode(chunk) if isinstance(chunk, bytes) else chunk
        if not text:
            return []
        start = max(0, len(self._buf) - _OVERLAP)
        self._buf += text
        out: list[str] = []
        while True:
            idx = _index_of_event_boundary(self._buf, start)
            if idx == -1:
                break
            raw_event = self._buf[:idx]
            if raw_event.endswith("\r"):
                # "\r\n" + "\n" also ends an event; the TS SDK would leave the
                # "\r" on the last data line.
                raw_event = raw_event[:-1]
            # Drop the separator itself, like `.replace(/^(\r?\n){2}/, "")` in TS.
            separator = 2 if self._buf.startswith("\n\n", idx) else 4
            self._buf = self._buf[idx + separator :]
            start = 0
            data = _collect_data_lines(raw_event)
            if data is not None:
                out.append(data)
        return out

    def finish(self) -> list[str]:
        """Flushes the decoder and returns the trailing event, if it has data."""
        out = self.feed(self._decoder.decode(b"", final=True))
        rest, self._buf = self._buf, ""
        data = _collect_data_lines(rest)
        if data is not None:
            out.append(data)
        return out


def _index_of_event_boundary(buf: str, start: int) -> int:
    a = buf.find("\n\n", start)
    b = buf.find("\r\n\r\n", start)
    if a == -1:
        return b
    if b == -1:
        return a
    return min(a, b)


def _collect_data_lines(event: str) -> str | None:
    data = [
        _LEADING_WS.sub("", line[5:], count=1)
        for line in _LINE_SPLIT.split(event)
        if line.startswith("data:")
    ]
    if not data:
        return None
    return "\n".join(data)
