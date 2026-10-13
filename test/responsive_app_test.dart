import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/app.dart';
import 'package:llmquota/models/quota.dart';
import 'package:llmquota/services/preferences.dart';
import 'package:llmquota/services/quota_controller.dart';

import 'widget_test.dart' as fixtures show TestWindow;

void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    for (final size in [
      const Size(340, 260),
      const Size(380, 800),
      const Size(800, 600),
      const Size(1280, 720),
      const Size(1920, 1080),
      const Size(3840, 2160),
    ]) {
      testWidgets('Normal app fits $size at text scale $scale', (tester) async {
        await tester.binding.setSurfaceSize(size);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        final controller = QuotaController()..setDemo(true);
        await controller.refresh();
        for (final account in controller.accounts) {
          controller.snapshots[account.id] = QuotaSnapshot(
            provider: account.provider,
            accountId: account.id,
            accountLabel:
                'An unusually long account label that remains readable',
            planName: 'An unusually long subscription plan description',
            source: 'Responsive fixture',
            observedAt: DateTime.now(),
            status: QuotaStatus.demo,
            windows: [
              QuotaWindow(
                id: 'long',
                label: 'A very long rolling quota window description',
                usedPercent: 30,
              ),
            ],
          );
        }
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await tester.binding.setSurfaceSize(null);
        });
        await tester.pumpWidget(
          QuotaApp(
            controller: controller,
            window: fixtures.TestWindow(),
            preferences: const OverlayPreferences(),
            savePreferences: (_) async {},
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final codex = tester.getTopLeft(find.text('Codex'));
        final claude = tester.getTopLeft(find.text('Claude'));
        if (size.width >= 1280) {
          expect(claude.dy, codex.dy);
          expect(claude.dx, greaterThan(codex.dx));
        } else if (size.width <= 380) {
          expect(claude.dy, greaterThan(codex.dy));
        }
        expect(
          find.byTooltip('Overlay settings').hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Overlay settings'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Display settings'));
        await tester.tap(find.text('Display settings'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
