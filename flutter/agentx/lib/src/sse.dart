/// Incremental Server-Sent-Events parser used by `ExecutorClient.streamMessage`.
///
/// It mirrors the TypeScript SDK exactly: events are separated by a blank
/// line (`\n\n` or `\r\n\r\n`, whichever comes first); within an event only
/// `data:` lines count (one leading whitespace character is stripped from each
/// value) and multiple data lines are joined with `\n`; `event:`, `id:`,
/// `retry:` and comment (`:`) lines are ignored, as are events without any
/// data line. Feed it already-decoded text with [add] and call [close] at end
/// of stream to flush a final event that was not followed by a blank line.
class SseParser {
  String _buffer = '';

  /// Appends [chunk] and returns the `data` of every event it completed.
  List<String> add(String chunk) {
    final buffer = _buffer + chunk;
    final out = <String>[];
    var start = 0;
    while (true) {
      final lf = buffer.indexOf('\n\n', start);
      final crlf = buffer.indexOf('\r\n\r\n', start);
      final int idx;
      final int separatorLength;
      if (lf == -1 && crlf == -1) break;
      if (crlf == -1 || (lf != -1 && lf < crlf)) {
        idx = lf;
        separatorLength = 2;
      } else {
        idx = crlf;
        separatorLength = 4;
      }
      final data = collectDataLines(buffer.substring(start, idx));
      if (data != null) out.add(data);
      start = idx + separatorLength;
    }
    _buffer = buffer.substring(start);
    return out;
  }

  /// Flushes the buffered remainder at end of stream: returns its `data`, or
  /// `null` when it holds no data line.
  String? close() {
    final data = collectDataLines(_buffer);
    _buffer = '';
    return data;
  }

  static final _lineBreak = RegExp(r'\r?\n');
  static final _leadingSpace = RegExp(r'^\s');

  /// The joined `data:` values of one raw event, or `null` if it has none.
  static String? collectDataLines(String event) {
    final data = <String>[
      for (final line in event.split(_lineBreak))
        if (line.startsWith('data:')) line.substring(5).replaceFirst(_leadingSpace, ''),
    ];
    return data.isEmpty ? null : data.join('\n');
  }
}
