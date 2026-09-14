import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/file_changes.dart';

void main() {
  test('parses official review payload and preserves exact fields', () {
    final result = parseFileChanges({
      'files': 2,
      'additions': 5,
      'deletions': 2,
      'state': 'active',
      'items': [
        {
          'path': 'lib/a.dart',
          'additions': 1,
          'deletions': 1,
          'writeCount': 2,
          'toolNames': ['edit'],
          'patches': [
            {
              'oldStart': 1,
              'oldLines': 2,
              'newStart': 1,
              'newLines': 2,
              'lines': [' old', '-old one', '+new one'],
            }
          ],
        },
        {
          'path': 'lib/b.dart',
          'additions': 4,
          'deletions': 1,
          'writeCount': 1,
          'toolNames': [],
          'patches': [],
        },
      ],
    });

    expect(result.files, 2);
    expect(result.additions, 5);
    expect(result.deletions, 2);
    expect(result.state, 'active');
    expect(result.items.map((e) => e.path), ['lib/a.dart', 'lib/b.dart']);
    expect(result.items.first.writeCount, 2);
    expect(result.items.first.toolNames, ['edit']);
    expect(result.items.first.patches.single.lines,
        [' old', '-old one', '+new one']);
    expect(result.problems, isEmpty);
  });

  test('aggregates snapshot turns without inventing unavailable diffs', () {
    final result = parseFileChanges({
      'fileChanges': [
        {
          'turnIndex': 1,
          'fileState': 'applied',
          'snapshots': [
            {
              'path': 'new.txt',
              'beforeContent': null,
              'afterContent': 'one\ntwo\n',
              'writeCount': 1,
            },
            {
              'path': 'missing.txt',
              'beforeContent': 'old',
              'afterContent': null,
              'writeCount': 0,
            },
          ],
        }
      ],
    });

    expect(result.items.map((e) => e.path), ['missing.txt', 'new.txt']);
    final missing = result.items.first;
    expect(missing.problems, contains('afterContent missing or unavailable'));
    expect(missing.patches, isEmpty);
    final added = result.items.last;
    expect(added.additions, 2);
    expect(added.deletions, 0);
    expect(added.patches.single.lines, ['+one', '+two']);
    expect(result.fileState, 'applied');
  });

  test('preserves large-content refs without inventing a full-content fetch',
      () {
    final result = parseFileChanges({
      'fileChanges': [
        {
          'turnIndex': 1,
          'fileState': 'applied',
          'snapshots': [
            {
              'path': 'large.txt',
              'beforeContent': null,
              'afterContent': 'preview',
              'writeCount': 1,
              'contentRefs': [
                {
                  'field': 'afterContent',
                  'refId': 'ref-1',
                  'hash': 'sha256:synthetic',
                  'fullBytes': 4096,
                  'previewBytes': 64,
                }
              ],
            }
          ],
        }
      ],
    });

    final ref = result.items.single.contentRefs.single;
    expect(ref.field, 'afterContent');
    expect(ref.refId, 'ref-1');
    expect(ref.fullBytes, 4096);
    expect(ref.previewBytes, 64);
    expect(result.fileState, 'applied');
  });

  test('marks malformed fields and binary content instead of fabricating data',
      () {
    final result = parseFileChanges({
      'files': -1,
      'additions': 'bad',
      'deletions': null,
      'state': 'unknown',
      'items': [
        {
          'path': 'blob.bin',
          'additions': 0,
          'deletions': 0,
          'writeCount': 1,
          'patches': [],
          'afterContent': 'text\x00binary',
        }
      ],
    });

    expect(result.problems, isNotEmpty);
    expect(result.state, isNull);
    expect(result.items.single.looksBinary, isTrue);
    expect(result.items.single.writeCount, 1);
  });

  test('fallback LCS keeps context and exact changed lines', () {
    final hunk = buildDiffHunk(
      before: 'one\nold two\nthree\n',
      after: 'one\nnew two\nthree\n',
    );
    expect(hunk.lines, [' one', '-old two', '+new two', ' three']);
    expect(hunk.oldLines, 3);
    expect(hunk.newLines, 3);
  });

  test('text-range diff keeps distant edits as separate hunks', () {
    final hunks = buildDiffHunks(
      before: 'head\nold one\nkeep\nold two\ntail',
      after: 'head\nnew one\nkeep\nnew two\ntail',
      context: 0,
      isTextRange: true,
    );
    expect(hunks, hasLength(2));
    expect(hunks.every((h) => h.isTextRange), isTrue);
    expect(hunks.first.lines, ['-old one', '+new one']);
    expect(hunks.last.lines, ['-old two', '+new two']);
  });

  test('text-range diff preserves empty text and trailing newline semantics',
      () {
    final created =
        buildDiffHunks(before: '', after: 'created\n', isTextRange: true);
    expect(created.single.lines, ['+created']);
    expect(created.single.newHasTrailingNewline, isTrue);
    final newlineOnly = buildDiffHunks(before: 'same', after: 'same\n');
    expect(newlineOnly.single.lines, ['-same', '+same']);
    expect(newlineOnly.single.oldHasTrailingNewline, isFalse);
    expect(newlineOnly.single.newHasTrailingNewline, isTrue);
  });

  test('large text range is bounded and explicitly marked', () {
    final before = List<String>.generate(300, (i) => 'old-$i').join('\n');
    final after = List<String>.generate(300, (i) => 'new-$i').join('\n');
    final hunks = buildDiffHunks(
      before: before,
      after: after,
      maxDiffCells: 100,
      maxOutputLines: 20,
      isTextRange: true,
    );
    expect(hunks, isNotEmpty);
    expect(hunks.any((h) => h.truncated), isTrue);
    expect(
        hunks
            .expand((h) => h.lines)
            .where((line) => line.contains('truncated')),
        isEmpty);
    expect(
        hunks.expand((h) => h.lines).every((line) =>
            line.startsWith('+old-') ||
            line.startsWith('-old-') ||
            line.startsWith('+new-') ||
            line.startsWith('-new-')),
        isTrue);
  });

  test('common prefix and suffix stay out of the diff working set', () {
    final prefix = List<String>.generate(2000, (i) => 'prefix-$i').join('\n');
    final suffix = List<String>.generate(2000, (i) => 'suffix-$i').join('\n');
    final hunks = buildDiffHunks(
      before: '$prefix\nold\n$suffix',
      after: '$prefix\nnew\n$suffix',
      context: 1,
      maxDiffCells: 1,
    );
    expect(hunks.single.lines, [' prefix-1999', '-old', '+new', ' suffix-0']);
    expect(hunks.single.truncated, isFalse);
  });

  test('long changed lines obey the character budget without fake lines', () {
    final hunks = buildDiffHunks(
      before: 'a' * 500000,
      after: 'b' * 500000,
      isTextRange: true,
    );
    final lines = hunks.expand((hunk) => hunk.lines).toList();
    expect(lines.fold<int>(0, (sum, line) => sum + line.length),
        lessThanOrEqualTo(100000));
    expect(hunks.any((hunk) => hunk.truncated), isTrue);
    expect(lines.any((line) => line.contains('truncated')), isFalse);
  });

  test('tool edit parser follows official aliases and keeps raw on bad patch',
      () {
    final edit = parseToolInlineDiff({
      'toolName': 'Edit',
      'input': {
        'file_path': 'lib/edit.dart',
        'old_string': 'old\n',
        'new_string': 'new\n',
      },
    })!;
    expect(edit.path, 'lib/edit.dart');
    expect(edit.fromPatch, isFalse);
    expect(edit.hunks.single.lines, ['-old', '+new']);

    final created = parseToolInlineDiff({
      'toolName': 'Write',
      'inputText': '{"file_path":"new.txt","content":"one\\ntwo"}',
    })!;
    expect(created.hunks.single.lines, ['+one', '+two']);

    final deleted = parseToolInlineDiff({
      'toolName': 'Delete',
      'input': {'path': 'gone.txt', 'oldContent': 'gone'},
    })!;
    expect(deleted.hunks.single.lines, ['-gone']);

    final badPatch = parseToolInlineDiff({
      'toolName': 'Edit',
      'input': {
        'path': 'lib/bad.dart',
        'patch': {'unknown': true},
        'oldText': 'old',
        'newText': 'new',
      },
    });
    expect(badPatch, isNull);
  });

  test('explicit patch wins over old/new text', () {
    final diff = parseToolInlineDiff({
      'toolName': 'Edit',
      'input': {
        'path': 'lib/patched.dart',
        'oldText': 'not used',
        'newText': 'not used',
        'patch': {
          'oldStart': 8,
          'oldLines': 1,
          'newStart': 8,
          'newLines': 1,
          'lines': ['-from patch', '+to patch'],
        },
      },
    })!;
    expect(diff.fromPatch, isTrue);
    expect(diff.hunks.single.lines, ['-from patch', '+to patch']);
  });

  test('multiple edit payloads remain separate text-range blocks', () {
    final diff = parseToolInlineDiff({
      'toolName': 'Edit',
      'input': {
        'path': 'lib/multi.dart',
        'edits': [
          {'oldText': 'one', 'newText': 'ONE'},
          {'oldText': 'two', 'newText': 'TWO'},
        ],
      },
    })!;
    expect(diff.hunks, hasLength(2));
    expect(diff.hunks.map((h) => h.rangeLabel), ['编辑 1', '编辑 2']);
    expect(diff.hunks.map((h) => h.lines), [
      ['-one', '+ONE'],
      ['-two', '+TWO'],
    ]);
  });

  test('parses official rewind preview groups and reason enums', () {
    final preview = parseFileRewindPreview({
      'canApply': true,
      'safeFiles': [
        {
          'action': 'restore',
          'operationCount': 2,
          'path': 'lib/a.dart',
          'toolNames': ['edit'],
        }
      ],
      'unsafeFiles': [
        {
          'operationCount': 1,
          'path': 'lib/conflict.dart',
          'reason': 'external_modified',
          'currentHash': 'sha256:current',
          'expectedHash': 'sha256:expected',
          'toolNames': [],
        }
      ],
      'ignoredFiles': [
        {
          'operationCount': 1,
          'path': 'lib/ignored.dart',
          'reason': 'bash_ignored',
          'toolNames': ['bash'],
        }
      ],
    });

    expect(preview.canApply, isTrue);
    expect(preview.safeFiles.single.action, 'restore');
    expect(preview.safeFiles.single.operationCount, 2);
    expect(preview.unsafeFiles.single.reason, 'external_modified');
    expect(preview.unsafeFiles.single.expectedHash, 'sha256:expected');
    expect(preview.ignoredFiles.single.reason, 'bash_ignored');
    expect(preview.problems, isEmpty);
  });

  test('rejects malformed rewind preview without inventing safety', () {
    expect(
      () => parseFileRewindPreview({'canApply': 'yes'}),
      throwsA(isA<FileChangesFormatException>()),
    );
    final preview = parseFileRewindPreview({
      'canApply': true,
      'safeFiles': [],
      'unsafeFiles': [
        {
          'operationCount': 1,
          'path': 'lib/bad.dart',
          'reason': 'unknown_reason',
          'toolNames': [],
        }
      ],
      'ignoredFiles': [],
    });
    expect(preview.canApply, isTrue);
    expect(preview.unsafeFiles, isEmpty);
    expect(preview.problems, ['unsafeFiles missing or invalid']);
  });

  test('parses apply command result and accepted/duplicate closing states', () {
    for (final status in ['accepted', 'duplicate']) {
      final result = parseFileRewindApply({
        'commandId': 'command-1',
        'status': status,
        'revisionAtDecision': 8,
        'result': {
          'type': 'applyFileRewind',
          'applied': true,
          'response': 'rewind-response',
          'preview': {
            'canApply': true,
            'safeFiles': [],
            'unsafeFiles': [],
            'ignoredFiles': [],
          },
        },
      });
      expect(result.status, status);
      expect(result.applied, isTrue);
      expect(result.response, 'rewind-response');
      expect(result.preview?.canApply, isTrue);
      expect(result.problems, isEmpty);
    }
    expect(
      () => parseFileRewindApply({
        'status': 'accepted',
        'result': {'type': 'other'},
      }),
      throwsA(isA<FileChangesFormatException>()),
    );
  });
}
