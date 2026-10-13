import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/app.dart';
import 'package:llmqueta/debug_dialog.dart';
import 'package:llmqueta/models/quota.dart';
import 'package:llmqueta/models/quota_account.dart';
import 'package:llmqueta/services/preferences.dart';
import 'package:llmqueta/services/quota_controller.dart';

import 'widget_test.dart' as fixtures show TestWindow;

void main() {
  testWidgets('diagnostics include hidden accounts without private details',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(340, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const privateLabel = 'private@example.com';
    final privatePath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}private-account';
    const privateMessage = 'secret-token in provider response';
    final controller = QuotaController(
      debugMode: true,
      accounts: [
        QuotaAccount(
          id: 'codex',
          provider: ProviderKind.codex,
          label: privateLabel,
          configurationDirectory: privatePath,
        ),
      ],
      accountFetcher: (account) async => QuotaSnapshot(
        provider: account.provider,
        windows: [],
        observedAt: DateTime.utc(2026, 10, 13),
        source: privatePath,
        status: QuotaStatus.unavailable,
        message: privateMessage,
      ),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.visibleSnapshots, isEmpty);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DebugDialog(controller: controller)),
    ));

    expect(find.text('Account 1 · codex'), findsOneWidget);
    expect(find.text('Displayed status: unavailable'), findsOneWidget);
    expect(find.textContaining('Fetch status: unavailable'), findsOneWidget);
    expect(
        find.textContaining('Previous data retained: false'), findsOneWidget);
    for (final privateValue in [privateLabel, privatePath, privateMessage]) {
      expect(find.textContaining(privateValue), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('debug indicator keeps demo data explicit', (tester) async {
    await tester.binding.setSurfaceSize(const Size(340, 720));
    final controller = QuotaController()..setDemo(true);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(QuotaApp(
      controller: controller,
      window: fixtures.TestWindow(),
      preferences: const OverlayPreferences(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('DEMO · SAMPLE DATA'), findsOneWidget);

    await tester.tap(find.byTooltip('Overlay settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is CheckedPopupMenuItem<String> && widget.value == 'debug'));
    await tester.pumpAndSettle();
    expect(find.byType(DebugDialog), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('DEBUG · DEMO DATA'), findsOneWidget);
    expect(controller.demo, isTrue);
    expect(
        controller.visibleSnapshots,
        everyElement(isA<QuotaSnapshot>().having(
            (snapshot) => snapshot.status, 'status', QuotaStatus.demo)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings toggle enables diagnostics and disabling clears them',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(340, 720));
    final controller = QuotaController(
      accounts: [QuotaAccount.defaults.first],
      accountFetcher: (account) async => QuotaSnapshot(
        provider: account.provider,
        windows: [],
        observedAt: DateTime.utc(2026, 10, 13),
        source: 'Fixture',
        status: QuotaStatus.unavailable,
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(QuotaApp(
      controller: controller,
      window: fixtures.TestWindow(),
      preferences: const OverlayPreferences(),
    ));
    await tester.tap(find.byTooltip('Overlay settings'));
    await tester.pumpAndSettle();
    expect(find.text('Debug diagnostics'), findsNothing);
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is CheckedPopupMenuItem<String> && widget.value == 'debug'));
    await tester.pumpAndSettle();
    expect(controller.debugMode, isTrue);
    expect(find.byType(DebugDialog), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await controller.refresh();
    await tester.pumpAndSettle();
    expect(controller.diagnostics, hasLength(1));
    await tester.tap(find.byTooltip('Overlay settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Debug diagnostics'));
    await tester.pumpAndSettle();
    expect(find.byType(DebugDialog), findsOneWidget);
    expect(find.textContaining('Fetch status: unavailable'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Overlay settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is CheckedPopupMenuItem<String> && widget.value == 'debug'));
    await tester.pumpAndSettle();
    expect(controller.debugMode, isFalse);
    expect(controller.diagnostics, isEmpty);
    await tester.tap(find.byTooltip('Overlay settings'));
    await tester.pumpAndSettle();
    expect(find.text('Debug diagnostics'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
