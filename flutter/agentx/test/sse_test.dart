import 'package:lowcoai_agentx/src/sse.dart';
import 'package:test/test.dart';

/// Feeds [chunks] through a fresh parser and returns every event, including
/// the trailing one flushed by `close`.
List<String> parse(Iterable<String> chunks) {
  final parser = SseParser();
  final out = [for (final c in chunks) ...parser.add(c)];
  final trailing = parser.close();
  return [...out, if (trailing != null) trailing];
}

/// Every way of cutting [text] into pieces of [size] characters.
List<String> chunked(String text, int size) => [
      for (var i = 0; i < text.length; i += size)
        text.substring(i, i + size > text.length ? text.length : i + size)
    ];

void main() {
  test('LF-separated events', () {
    expect(parse(['data: a\n\ndata: b\n\n']), ['a', 'b']);
  });

  test('CRLF-separated events', () {
    expect(parse(['data: a\r\n\r\ndata: b\r\n\r\n']), ['a', 'b']);
  });

  test('multiple data lines are joined with \\n', () {
    expect(parse(['data: {"a":\ndata: 1}\n\n']), ['{"a":\n1}']);
    expect(parse(['data: x\r\ndata: y\r\n\r\n']), ['x\ny']);
  });

  test('exactly one leading whitespace character is stripped', () {
    expect(parse(['data:no-space\n\n']), ['no-space']);
    expect(parse(['data:  two\n\n']), [' two']);
    expect(parse(['data:\ttab\n\n']), ['tab']);
    expect(parse(['data:\n\n']), ['']);
    expect(parse(['data: \n\n']), ['']);
  });

  test('non-data fields, comments and data-less events are ignored', () {
    expect(
      parse([': ping\n\nevent: message\nid: 7\nretry: 10\ndata: x\n\nevent: noop\n\n']),
      ['x'],
    );
    expect(parse(['datum: x\n\ndata\n\n']), isEmpty);
  });

  test('a trailing event without a blank line is flushed on close', () {
    expect(parse(['data: a\n\ndata: tail']), ['a', 'tail']);
    expect(parse(['data: a\n\ndata: tail\n']), ['a', 'tail']);
    expect(parse(['data: a\n\n: just a comment']), ['a']);
    expect(parse(['']), isEmpty);
  });

  test('add returns events as soon as they complete', () {
    final parser = SseParser();
    expect(parser.add('data: a'), isEmpty);
    expect(parser.add('\n'), isEmpty);
    expect(parser.add('\ndata: b\n\ndata: c\r'), ['a', 'b']);
    expect(parser.add('\n\r'), isEmpty);
    expect(parser.add('\n'), ['c']);
    expect(parser.close(), isNull);
  });

  test('the earliest separator wins, as in the TypeScript SDK', () {
    // "\r\n\n" contains "\n\n": the event ends there and keeps its trailing CR.
    expect(parse(['data: a\r\n\ndata: b\n\n']), ['a\r', 'b']);
    // "\n\r\n" is not a separator in either form.
    expect(parse(['data: a\n\r\ndata: b\n\n']), ['a\nb']);
  });

  test('every chunk size yields the same events', () {
    const text = ': hi\r\n\r\nevent: m\r\ndata: {"t":"é👋"}\r\n\r\n'
        'data: one\ndata:two\n\nid: 3\n\ndata: tail';
    const expected = ['{"t":"é👋"}', 'one\ntwo', 'tail'];
    for (var size = 1; size <= text.length; size++) {
      expect(parse(chunked(text, size)), expected, reason: 'chunk size $size');
    }
  });

  test('collectDataLines', () {
    expect(SseParser.collectDataLines('event: x\ndata: 1\ndata: 2'), '1\n2');
    expect(SseParser.collectDataLines('event: x'), isNull);
  });
}
