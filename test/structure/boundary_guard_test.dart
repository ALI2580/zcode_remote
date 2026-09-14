import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// S5 structure guard (references/optimization/structure-todolist.md).
/// Locks the architectural invariants the optimization and portrait tasks
/// rely on:
///   1. `lib/protocol` stays pure Dart: no Flutter, no `dart:ui`, and no
///      imports of `lib/ui` or `lib/state` (import/export/part, relative or
///      package paths, including conditional-import stubs).
///   2. `lib/state` never imports `lib/ui` (UI depends on state, never the
///      reverse).
///   3. `lib/protocol` has no import cycles among its own files.

final _root = Directory('lib');

/// Normalized (forward-slash) repo-relative path of [file].
///
/// `listSync` yields backslash paths on Windows; every graph key and resolved
/// target must share one separator space or edges silently vanish on Windows
/// while CI (Linux) sees the full graph.
String _posixPath(File file) => file.path.replaceAll('\\', '/');

List<File> dartFiles(String prefix) => _root
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => _posixPath(f).startsWith('$prefix/') && f.path.endsWith('.dart'))
    .toList();

final _uriPattern = RegExp(r'''['"]([^'"]+)['"]''');

/// All URI strings declared by [file] (import/export/part), including every
/// conditional-import branch (`import 'a.dart' if (...) 'b.dart'`).
List<String> declaredUris(File file) {
  final uris = <String>[];
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('import ') &&
        !trimmed.startsWith('export ') &&
        !trimmed.startsWith('part ')) {
      continue;
    }
    uris.addAll(_uriPattern.allMatches(line).map((m) => m.group(1)!));
  }
  return uris;
}

/// Collapse `.`/`..` segments in a forward-slash path.
String _normalizePosix(String path) {
  final out = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isNotEmpty && out.last != '..') {
        out.removeLast();
        continue;
      }
    }
    out.add(segment);
  }
  return out.join('/');
}

/// Resolve a declared URI to a repo file path when it points inside the
/// package; returns null for dart:* and package: paths of other packages.
String? resolvePackageUri(File file, String uri) {
  const lib = 'lib/';
  if (uri.startsWith('package:zcode_remote/')) {
    return '$lib${uri.substring('package:zcode_remote/'.length)}';
  }
  if (uri.startsWith('dart:')) return null;
  // relative path, normalized against the file directory
  final dirSegments = _posixPath(file).split('/')..removeLast();
  return _normalizePosix('${dirSegments.join('/')}/$uri');
}

void main() {
  test('lib/protocol imports stay pure Dart', () {
    final violations = <String>[];
    for (final file in dartFiles('lib/protocol')) {
      for (final uri in declaredUris(file)) {
        final banned = uri.startsWith('package:flutter/') ||
            uri.startsWith('dart:ui') ||
            uri.contains('/ui/') ||
            uri.contains('/state/') ||
            uri.startsWith('../ui/') ||
            uri.startsWith('../state/');
        if (banned) violations.add('${file.path}: $uri');
      }
    }
    expect(violations, isEmpty,
        reason: 'protocol must not depend on Flutter, ui or state layers');
  });

  test('lib/state never imports lib/ui', () {
    final violations = <String>[];
    for (final file in dartFiles('lib/state')) {
      for (final uri in declaredUris(file)) {
        final banned = uri.contains('/ui/') || uri.startsWith('../ui/');
        if (banned) violations.add('${file.path}: $uri');
      }
    }
    expect(violations, isEmpty, reason: 'dependency direction: ui -> state');
  });

  test('lib/protocol has no import cycles', () {
    final imports = <String, Set<String>>{};
    for (final file in dartFiles('lib/protocol')) {
      final path = file.path.replaceAll('\\', '/');
      imports[path] = {};
      for (final uri in declaredUris(file)) {
        final target = resolvePackageUri(file, uri);
        if (target != null && target.startsWith('lib/protocol/')) {
          imports[path]!.add(target);
        }
      }
    }
    // DFS cycle detection
    const white = 0, grey = 1, black = 2;
    final color = <String, int>{};
    String? cycleNode;
    void visit(String node, List<String> stack) {
      color[node] = grey;
      stack.add(node);
      for (final next in imports[node] ?? const <String>{}) {
        if ((color[next] ?? white) == grey) {
          cycleNode = next;
        } else if ((color[next] ?? white) == white) {
          visit(next, stack);
        }
      }
      color[node] = black;
      stack.removeLast();
    }

    for (final node in imports.keys) {
      if ((color[node] ?? white) == white) visit(node, <String>[]);
    }
    expect(cycleNode, isNull, reason: 'protocol files must stay acyclic');
  });
}
