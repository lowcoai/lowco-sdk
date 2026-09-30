from __future__ import annotations

import pytest

from lowcoai.agentx._sse import SSEParser


def parse(*chunks: bytes | str) -> list[str]:
    parser = SSEParser()
    out: list[str] = []
    for chunk in chunks:
        out.extend(parser.feed(chunk))
    out.extend(parser.finish())
    return out


SAMPLE = (
    ": keep-alive comment\n"
    "event: message\n"
    'data: {"kind":"message","parts":[{"kind":"text","text":"héllo"}]}\n'
    "\n"
    "id: 2\r\n"
    "data: line one\r\n"
    "data:line two\r\n"
    "data:   indented\r\n"
    "\r\n"
    ": only a comment\n"
    "retry: 1000\n"
    "\n"
    "\n"
    "\n"
    "data: é 😀 ü\n"
    "\n"
    "event: done\n"
    "data: [DONE]"
)
EXPECTED = [
    '{"kind":"message","parts":[{"kind":"text","text":"héllo"}]}',
    "line one\nline two\n  indented",
    "é 😀 ü",
    "[DONE]",
]


def test_parses_whole_stream() -> None:
    assert parse(SAMPLE) == EXPECTED
    assert parse(SAMPLE.encode()) == EXPECTED


def test_every_two_way_split_of_the_bytes_gives_the_same_events() -> None:
    raw = SAMPLE.encode()
    for i in range(len(raw) + 1):
        assert parse(raw[:i], raw[i:]) == EXPECTED, i


def test_every_three_way_split_of_the_text_gives_the_same_events() -> None:
    for i in range(len(SAMPLE) + 1):
        for j in range(i, len(SAMPLE) + 1, 7):
            assert parse(SAMPLE[:i], SAMPLE[i:j], SAMPLE[j:]) == EXPECTED, (i, j)


def test_byte_by_byte_feed() -> None:
    raw = SAMPLE.encode()
    assert parse(*(raw[i : i + 1] for i in range(len(raw)))) == EXPECTED


def test_events_are_returned_as_soon_as_they_complete() -> None:
    parser = SSEParser()
    assert parser.feed("data: a\n") == []
    assert parser.feed("\ndata: b\r\n\r") == ["a"]
    assert parser.feed("\n") == ["b"]
    assert parser.feed("data: c") == []
    assert parser.finish() == ["c"]
    assert parser.finish() == []


@pytest.mark.parametrize(
    ("stream", "expected"),
    [
        ("data: x\n\n", ["x"]),
        ("data:x\n\n", ["x"]),
        ("data:  x\n\n", [" x"]),  # only one leading whitespace character is removed
        ("data:\tx\n\n", ["x"]),  # TS strips any single whitespace (`/^\s/`)
        ("data:\n\n", [""]),  # an empty data line is still data
        ("data\n\n", []),  # no colon: not a data line (as in the TS SDK)
        ("event: ping\nid: 1\n\n", []),
        (": comment\n\n", []),
        ("\n\n\n\n", []),
        ("data: a\ndata: b\n\n", ["a\nb"]),
        ("data: a\r\ndata: b\r\n\r\n", ["a\nb"]),
        ("data: a\n\ndata: b\r\n\r\ndata: c", ["a", "b", "c"]),
        ("data: trailing\n", ["trailing"]),
        ("data: trailing", ["trailing"]),
        ("data: a\r\n\ndata: b\n\n", ["a", "b"]),
        ("data: 1\n\n\n\ndata: 2\n\n", ["1", "2"]),
    ],
)
def test_semantics(stream: str, expected: list[str]) -> None:
    assert parse(stream) == expected
    assert parse(stream.encode()) == expected


def test_leading_bom_is_dropped_when_decoding_bytes() -> None:
    assert parse(b"\xef\xbb", b"\xbfdata: bom\n\n") == ["bom"]


def test_multibyte_character_split_across_chunks() -> None:
    raw = "data: 😀\n\n".encode()
    cut = raw.index(b"\xf0") + 2
    assert parse(raw[:cut], raw[cut:]) == ["😀"]


def test_invalid_utf8_is_replaced_not_raised() -> None:
    assert parse(b"data: \xff\n\n") == ["\ufffd"]
    # A truncated sequence at end-of-stream is flushed as a replacement char.
    assert parse(b"data: \xe2\x82") == ["\ufffd"]
