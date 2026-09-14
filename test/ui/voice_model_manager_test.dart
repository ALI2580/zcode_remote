import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/ui/voice_model_manager.dart';
import 'package:zcode_remote/voice/voice_model_events.dart';
import 'package:zcode_remote/voice/voice_download_state.dart';
import 'package:zcode_remote/voice/voice_model_store.dart';
import 'package:zcode_remote/voice/voice_models.dart';

class FakeStore implements VoiceModelStore {
  @override
  final progress = <String, double>{};

  @override
  final downloadStates = <String, VoiceDownloadState>{};
  final downloaded = <String>{};
  final downloads = <String, Completer<void>>{};
  int? totalBytes = 1000;
  String? enabled;

  Future<Directory> directory(VoiceModelInfo model) async =>
      Directory.systemTemp;

  @override
  Future<bool> isDownloaded(VoiceModelInfo model) async =>
      downloaded.contains(model.id);

  @override
  Future<String?> enabledModelId() async => enabled;

  @override
  Future<void> setEnabled(VoiceModelInfo model) async {
    if (!downloaded.contains(model.id)) throw StateError('模型尚Not downloaded');
    enabled = model.id;
    VoiceModelEvents.notifyChanged();
  }

  @override
  Future<void> disable(VoiceModelInfo model) async {
    if (enabled == model.id) {
      enabled = null;
      VoiceModelEvents.notifyChanged();
    }
  }

  @override
  Future<void> download(VoiceModelInfo model) async {
    final completer = Completer<void>();
    downloads[model.id] = completer;
    progress[model.id] = 0.5;
    downloadStates[model.id] = VoiceDownloadState(
        VoiceDownloadPhase.downloading,
        received: 500,
        total: totalBytes);
    VoiceModelEvents.notifyChanged();
    await completer.future;
    downloaded.add(model.id);
    progress[model.id] = 1;
    downloadStates.remove(model.id);
    VoiceModelEvents.notifyChanged();
  }

  @override
  void cancelDownload(VoiceModelInfo model) {
    progress[model.id] = 0.4;
    downloadStates.remove(model.id);
    downloads
        .remove(model.id)
        ?.completeError(StateError('Model download cancelled'));
    VoiceModelEvents.notifyChanged();
  }

  @override
  Future<void> delete(VoiceModelInfo model) async {
    await disable(model);
    downloaded.remove(model.id);
    progress.remove(model.id);
    VoiceModelEvents.notifyChanged();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpManager(WidgetTester tester, FakeStore store) async {
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [DefaultCupertinoLocalizations.delegate],
        home: Scaffold(
            body: ListView(children: [
          VoiceModelManager(store: store, models: [voiceModels.first])
        ]))));
    await tester.pumpAndSettle();
  }

  testWidgets('download can be cancelled and retried atomically',
      (tester) async {
    final store = FakeStore();
    await pumpManager(tester, store);
    expect(find.text('Not downloaded'), findsOneWidget);

    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(store.progress[voiceModels.first.id], 0.5);
    // U25: the row shows received and total bytes, not a bare percentage.
    expect(find.textContaining('Downloading'), findsOneWidget);
    expect(find.textContaining('500 B / 1000 B'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(store.downloaded, isEmpty);
    expect(find.textContaining('Model download cancelled'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    store.downloads[voiceModels.first.id]!.complete();
    await tester.pump();
    expect(await store.isDownloaded(voiceModels.first), isTrue);
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text('Enable'), findsOneWidget);
  });

  testWidgets('enable, disable and delete update model state', (tester) async {
    final store = FakeStore()..downloaded.add(voiceModels.first.id);
    await pumpManager(tester, store);
    expect(find.text('Downloaded'), findsOneWidget);

    await tester.tap(find.text('Enable'));
    await tester.pump();
    expect(store.enabled, voiceModels.first.id);
    expect(find.text('Enabled'), findsOneWidget);

    await tester.tap(find.text('Disable'));
    await tester.pump();
    expect(store.enabled, isNull);
    expect(find.text('Downloaded'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(store.downloaded, isEmpty);
    expect(find.text('Not downloaded'), findsOneWidget);
  });

  testWidgets('unknown total length keeps an indeterminate bar with bytes',
      (tester) async {
    final store = FakeStore();
    store.totalBytes = null;
    await pumpManager(tester, store);
    await tester.tap(find.text('Download'));
    await tester.pump();
    // No fabricated percentage: received bytes plus an indeterminate bar.
    expect(find.textContaining('500 B'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator).first);
    expect(bar.value, isNull);
  });
}
