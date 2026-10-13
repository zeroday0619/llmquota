import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbt_fluent2_ui/gbt_fluent2_ui.dart';
import 'package:llmquota/app_theme.dart';
import 'package:llmquota/services/preferences.dart';
import 'package:llmquota/hud_overlay.dart';
import 'package:llmquota/services/quota_controller.dart';
import 'package:llmquota/usage_summary.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('HUD and usage labels follow $brightness colors', (
      tester,
    ) async {
      final controller = QuotaController()..setDemo(true);
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: brightness,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: applicationTheme(
            brightness == Brightness.light
                ? AppThemeMode.light
                : AppThemeMode.dark,
          ).copyWith(colorScheme: scheme),
          home: Scaffold(
            body: HudOverlay(
              controller: controller,
              resetLabel: (_, __) => 'Reset unavailable',
              onDrag: () async {},
              onClose: () async {},
              onExit: () {},
            ),
          ),
        ),
      );
      final surface = tester.widget<FluentContainer>(
        find
            .descendant(
              of: find.byType(HudOverlay),
              matching: find.byType(FluentContainer),
            )
            .first,
      );
      expect(surface.color, scheme.surface);
      final title = tester.widget<Text>(find.text('Quota · Demo'));
      expect(title.style!.color, scheme.onSurfaceVariant);
      final usage = find.byType(UsageSummary).first;
      final labels = tester.widgetList<Text>(
        find.descendant(of: usage, matching: find.byType(Text)),
      );
      expect(labels.first.style!.color, scheme.onSurfaceVariant);
      final provider = tester.widget<Text>(find.text('Codex').first);
      final foreground = provider.style!.color!.computeLuminance();
      final background = scheme.surface.computeLuminance();
      final ratio = foreground > background
          ? (foreground + 0.05) / (background + 0.05)
          : (background + 0.05) / (foreground + 0.05);
      expect(ratio, greaterThan(4.5));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
