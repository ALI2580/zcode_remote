import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/composer_input.dart';
import 'package:zcode_remote/state/composer_references.dart';
import '../ui/fake_features.dart';

void main() {
  late ComposerInput input;
  late ComposerReferences references;
  late FeatureTransport transport;
  late DateTime now;
  String session = 'first';
  setUp(() {
    input = ComposerInput();
    transport = FeatureBridge().conversationTransport;
    now = DateTime.utc(2026, 9, 9);
    session = 'first';
    references = ComposerReferences(
        input: input,
        transport: transport,
        preparation: () => null,
        session: () => session,
        now: () => now);
  });
  tearDown(() {
    references.dispose();
    input.dispose();
  });
  Future<void> query(String text) async {
    input.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    await Future<void>.delayed(Duration.zero);
  }

  test(
      'empty file query lists files before directories and searches absolute keywords',
      () async {
    transport.files = transport.files.reversed.toList();
    await query('@');
    expect(references.entries.where((e) => e.category == 'files').first.label,
        'main.dart');
    await query('@Synthetic');
    expect(
        references.entries.where((e) => e.category == 'files'), hasLength(2));
  });

  test('file cache expires on reopening and a missed query refreshes only once',
      () async {
    await query('@');
    expect(transport.fileReads, 1);
    await query('');
    now = now.add(const Duration(seconds: 29));
    await query('@');
    expect(transport.fileReads, 1);
    await query('');
    now = now.add(const Duration(seconds: 1));
    await query('@');
    expect(transport.fileReads, 2);
    await query('@missing-file');
    expect(transport.fileReads, 3);
    input.selection = const TextSelection.collapsed(offset: 13);
    await Future<void>.delayed(Duration.zero);
    expect(transport.fileReads, 3);
  });

  test(
      'late catalogs and stale picks are discarded when the session scope changes',
      () async {
    await query('@');
    final stale = references.entries.first;
    final old = Completer<List<Map<String, dynamic>>>();
    transport.filesHandler = () => old.future;
    references.invalidate();
    session = 'second';
    transport.filesHandler = () async => [
          {'name': 'second.dart', 'relativePath': 'second.dart', 'type': 'file'}
        ];
    references.updateScope();
    await Future<void>.delayed(Duration.zero);
    old.complete([
      {'name': 'old.dart', 'relativePath': 'old.dart', 'type': 'file'}
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(references.entries.where((e) => e.category == 'files').single.label,
        'second.dart');
    expect(references.pick(stale), isFalse);
    expect(input.text, '@');
  });

  test(
      'one failed reference category leaves the other real categories available',
      () async {
    transport.filesHandler = () => Future.error(TimeoutException('files'));
    await query('@');
    expect(references.failed, contains('files'));
    expect(references.entries.any((e) => e.category == 'plugins'), isTrue);
    expect(references.entries.any((e) => e.category == 'sessions'), isTrue);
  });
}
