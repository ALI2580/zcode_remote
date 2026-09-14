import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/onboarding_wizard.dart';
import 'package:zcode_remote/ui/theme.dart';

void main() {
  Future<void> pumpWelcome(WidgetTester tester,
      {required void Function() onStart,
      required void Function() onOpenMigration,
      required void Function() onClose}) async {
    // Official dialog shell size: max-w-4xl (896) x max-h-168 (672).
    tester.view.physicalSize = const Size(896, 672);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ZInkTheme.light(),
        home: Scaffold(
            body: Align(
                child: SizedBox(
                    width: 896,
                    height: 672,
                    child: OnboardingWelcomePage(
                        onStart: onStart,
                        onOpenMigration: onOpenMigration,
                        onClose: onClose))))));
    await tester.pump();
  }

  testWidgets('welcome renders the official two-column copy', (tester) async {
    await pumpWelcome(tester,
        onStart: () {}, onOpenMigration: () {}, onClose: () {});
    // Left column: eyebrow pill, title, actions, bottom helper.
    expect(find.text('首次启动设置'), findsOneWidget);
    expect(find.text('欢迎使用 ZCode'), findsOneWidget);
    expect(find.text('开始使用 ZCode'), findsOneWidget);
    expect(find.text('数据迁移向导'), findsOneWidget);
    expect(find.text('可立即导入旧工具设置，或先跳过，稍后在设置中继续迁移。'),
        findsOneWidget);
    // Right hero panel keeps its tagline on single lines.
    expect(find.text('快速打开，专注工作。'), findsOneWidget);
    expect(find.text('选择一个工作区，继续上次的进度，保持界面干净清爽。'),
        findsOneWidget);
    // The old single-column header/footer copy must be gone.
    expect(find.text('选择如何开始第一次会话。'), findsNothing);
    expect(find.text('可随时跳过引导，稍后在设置中继续迁移。'), findsNothing);
  });

  testWidgets('welcome actions dispatch to their callbacks', (tester) async {
    var started = false;
    var migrationOpened = false;
    var closed = false;
    await pumpWelcome(tester,
        onStart: () => started = true,
        onOpenMigration: () => migrationOpened = true,
        onClose: () => closed = true);
    await tester.tap(find.text('开始使用 ZCode'));
    await tester.tap(find.text('数据迁移向导'));
    // Close button sits in the top-right corner of the dialog shell.
    await tester.tap(find.bySemanticsLabel('关闭'));
    await tester.pump();
    expect(started, isTrue);
    expect(migrationOpened, isTrue);
    expect(closed, isTrue);
  });

  testWidgets('welcome keeps actions and hero inside the 896x672 shell',
      (tester) async {
    await pumpWelcome(tester,
        onStart: () {}, onOpenMigration: () {}, onClose: () {});
    // The full-width actions span the left column, not pill-sized buttons.
    final start = tester.getRect(find.text('开始使用 ZCode'));
    final dialog = tester.getRect(find.byType(OnboardingWelcomePage));
    expect(dialog.width, 896);
    expect(dialog.height, 672);
    expect(start.left, greaterThan(dialog.left + 32));
    // Hero tagline stays on one line and inside the right half.
    final hero = tester.getRect(find.text('快速打开，专注工作。'));
    expect(hero.height, closeTo(36, 4));
    expect(hero.center.dx, greaterThan(dialog.center.dx));
  });
}
