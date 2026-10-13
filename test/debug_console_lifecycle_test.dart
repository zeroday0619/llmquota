import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/app.dart';
import 'package:llmquota/services/debug_console.dart';
import 'package:llmquota/services/preferences.dart';
import 'package:llmquota/services/quota_controller.dart';

import 'widget_test.dart' as fixtures show TestWindow;

class TestDebugConsole implements DebugConsoleWindow {
  int shows = 0;
  int closes = 0;
  QuotaController? lastController;

  @override
  Future<void> show(QuotaController controller) async {
    shows++;
    lastController = controller;
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  for (final hud in [false, true]) {
    testWidgets('initial debug mode opens console once with HUD $hud', (
      tester,
    ) async {
      final controller = QuotaController(debugMode: true, accounts: []);
      final console = TestDebugConsole();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        QuotaApp(
          controller: controller,
          window: fixtures.TestWindow(),
          preferences: OverlayPreferences(hud: hud),
          debugConsole: console,
        ),
      );
      await tester.pump();
      expect(console.shows, 1);
      expect(console.lastController, same(controller));
      controller.setDemo(true);
      await tester.pump();
      controller.setDemo(false);
      await tester.pump();
      expect(console.shows, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(console.closes, 1);
    });
  }

  testWidgets(
    'debug transitions open and close console and settings reopen it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(340, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = QuotaController(accounts: []);
      final console = TestDebugConsole();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        QuotaApp(
          controller: controller,
          window: fixtures.TestWindow(),
          preferences: const OverlayPreferences(),
          savePreferences: (_) async {},
          debugConsole: console,
        ),
      );
      await tester.pumpAndSettle();
      expect(console.shows, 0);
      controller.setDebugMode(true);
      await tester.pumpAndSettle();
      expect(console.shows, 1);
      controller.setDebugMode(true);
      controller.setDemo(true);
      await tester.pumpAndSettle();
      expect(console.shows, 1);

      await tester.tap(find.byTooltip('Overlay settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Debug settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open debug console'));
      await tester.pumpAndSettle();
      expect(console.shows, 2);
      controller.setDebugMode(false);
      await tester.pumpAndSettle();
      expect(console.closes, 1);
      controller.setDebugMode(true);
      await tester.pumpAndSettle();
      expect(console.shows, 3);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(console.closes, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
