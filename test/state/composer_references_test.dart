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

  test('backspacing after a mention removes the whole atomic reference',
      () async {
    input.insertReference(
        const TextRange(start: 0, end: 0),
        const ComposerReference(
            id: 'file',
            category: 'files',
            label: 'main.dart',
            value: 'lib/main.dart'));
    expect(input.text, '@main.dart ');
    expect(input.referenceCount, 1);
    input.value = TextEditingValue(
        text: input.text.substring(0, input.text.length - 1),
        selection: TextSelection.collapsed(offset: input.text.length - 1));
    expect(input.text, isEmpty);
    expect(input.referenceCount, 0);
  });

  test('deleting inside a visible mention removes the whole atomic reference',
      () async {
    input.insertReference(
        const TextRange(start: 0, end: 0),
        const ComposerReference(
            id: 'file',
            category: 'files',
            label: 'main.dart',
            value: 'lib/main.dart'));
    expect(input.text, '@main.dart ');
    expect(input.referenceCount, 1);
    final old = input.value;
    final broken = old.text.replaceRange(2, 3, '');
    input.value = TextEditingValue(
        text: broken, selection: const TextSelection.collapsed(offset: 2));
    expect(input.text, ' ');
    expect(input.referenceCount, 0);
  });

  test('CJK skill triggers map to the same candidates as ASCII dollars',
      () async {
    await query(r'$');
    expect(references.entries.where((e) => e.category == 'skills').first.label,
        'review-code');
    await query('￥');
    expect(references.entries.where((e) => e.category == 'skills').first.label,
        'review-code');
    input.value = const TextEditingValue(
        text: ' ￥中',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 1, end: 3));
    expect(references.open, isFalse);
    input.value = const TextEditingValue(
        text: ' ￥中',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange.empty);
    expect(references.open, isTrue);
  });

  test('runtime catalog changes invalidate stale skill candidates', () async {
    await query(r'$');
    expect(references.entries.where((e) => e.category == 'skills').first.label,
        'review-code');
    transport.skillItems = [
      {
        'id': 'runtime-skill',
        'name': 'fresh-skill',
        'path': 'skills/fresh.md',
        'scope': 'workspace',
        'description': 'Runtime refresh'
      }
    ];
    references.invalidate();
    await query(r'$');
    expect(references.entries.where((e) => e.category == 'skills').first.label,
        'fresh-skill');
  });

  test('failed catalogs retry and keep the reference panel usable', () async {
    var attempts = 0;
    transport.skillItems = [];
    transport.filesHandler = () async {
      attempts++;
      if (attempts == 1) {
        return Future.error(TimeoutException('synthetic file timeout'));
      }
      return [
        {'name': 'retry.dart', 'relativePath': 'lib/retry.dart', 'type': 'file'}
      ];
    };
    await query('@');
    expect(references.failed, contains('files'));
    await references.retry();
    expect(references.failed, isNot(contains('files')));
    expect(
        references.entries
            .where((e) => e.category == 'files')
            .map((e) => e.label),
        contains('retry.dart'));
  });

  test('removing and reinserting a mention restores serialized output',
      () async {
    const reference = ComposerReference(
        id: 'file',
        category: 'files',
        label: 'main.dart',
        value: 'lib/main.dart');
    input.insertReference(const TextRange(start: 0, end: 0), reference);
    expect(input.markdown, '[main.dart](./lib/main.dart) ');
    final withToken = input.value;
    input.value = TextEditingValue(
        text: withToken.text.replaceRange(0, withToken.text.length, ''),
        selection: const TextSelection.collapsed(offset: 0));
    expect(input.referenceCount, 0);
    input.insertReference(const TextRange(start: 0, end: 0), reference);
    expect(input.text, '@main.dart ');
    expect(input.referenceCount, 1);
    expect(input.markdown, '[main.dart](./lib/main.dart) ');
  });
}
