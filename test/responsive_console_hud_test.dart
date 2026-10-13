import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/app_theme.dart';
import 'package:llmquota/services/preferences.dart';
import 'package:llmquota/debug_console.dart';
import 'package:llmquota/hud_overlay.dart';
import 'package:llmquota/models/quota.dart';
import 'package:llmquota/services/quota_controller.dart';

void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    for (final size in [
      const Size(280, 140),
      const Size(320, 240),
      const Size(600, 400),
    ]) {
      testWidgets('HUD fits $size at text scale $scale', (tester) async {
        await tester.binding.setSurfaceSize(size);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() async {
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await tester.binding.setSurfaceSize(null);
        });
        final controller = QuotaController()..setDemo(true);
        controller.snapshots['long-label'] = QuotaSnapshot(
          provider: ProviderKind.antigravity,
          observedAt: DateTime.now(),
          source: 'Fixture',
          status: QuotaStatus.stale,
          planName: 'An unusually long subscription plan name',
          accountLabel:
              'An unusually long account label that should remain bounded',
          windows: [
            QuotaWindow(
              id: 'primary',
              label: 'An unusually long rolling quota window',
              usedPercent: 35,
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: applicationTheme(AppThemeMode.dark),
            home: Scaffold(
              body: HudOverlay(
                controller: controller,
                resetLabel: (resetTime, currentTime) =>
                    'A long reset time description',
                onDrag: () async {},
                onClose: () async {},
                onExit: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Return to window (Esc)'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      });
    }
    for (final size in [
      const Size(340, 260),
      const Size(800, 640),
      const Size(1920, 1080),
    ]) {
      testWidgets('Console fits $size at text scale $scale', (tester) async {
        await tester.binding.setSurfaceSize(size);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() async {
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await tester.binding.setSurfaceSize(null);
        });
        final lines = ValueNotifier<List<String>>([
          '[1.234] JSON-RPC TX ${'long payload ' * 30}',
        ]);
        await tester.pumpWidget(
          DebugConsoleApp(
            lines: lines,
            onClose: () {},
            onRefresh: () {},
            onClearLogs: () {},
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Metrics'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        lines.dispose();
      });
    }
  }
}
