import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/file_changes.dart';

void main() {
  test('review: a single huge line has a bounded visible text payload', () {
    final hunks = buildDiffHunks(
        before: List.filled(500000, 'a').join(),
        after: List.filled(500000, 'b').join(), isTextRange: true);
    final displayed = hunks.expand((h) => h.lines).fold<int>(0, (n, line) => n + line.length);
    expect(displayed, lessThanOrEqualTo(100000),
        reason: 'A line budget alone cannot protect the UI from megabyte lines.');
    expect(hunks.any((h) => h.truncated), isTrue);
  });
  test('review: pure addition respects the display budget and records truncation', () {
    final hunks = buildDiffHunks(before: '',
        after: List.generate(5000, (i) => 'new $i').join('\n'),
        isTextRange: true, maxOutputLines: 40);
    expect(hunks.expand((h) => h.lines).length, lessThanOrEqualTo(40));
    expect(hunks.any((h) => h.truncated), isTrue);
  });

  test('review: equivalent input encodings do not duplicate the edit', () {
    final input = {'file_path': 'a.dart', 'old_string': 'before', 'new_string': 'after'};
    final diff = parseToolInlineDiff({'toolName': 'Edit', 'input': input,
        'inputText': jsonEncode(input)});
    expect(diff, isNotNull);
    expect(diff!.hunks.expand((h) => h.lines).where((line) => line == '+after'), hasLength(1));
  });

  test('review: truncation metadata is not fabricated added or removed file text', () {
    final hunks = buildDiffHunks(
        before: List.generate(200, (i) => 'old $i').join('\n'),
        after: List.generate(200, (i) => 'new $i').join('\n'),
        maxDiffCells: 50, maxOutputLines: 40, isTextRange: true);
    for (final line in hunks.expand((h) => h.lines)) {
      if (line.startsWith('+')) expect(line.substring(1).startsWith('new '), isTrue);
      if (line.startsWith('-')) expect(line.substring(1).startsWith('old '), isTrue);
    }
  });
}
