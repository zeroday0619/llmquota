import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbt_fluent2_ui/gbt_fluent2_ui.dart';
import 'package:llmquota/app.dart';
import 'package:llmquota/debug_console.dart';
import 'package:llmquota/services/preferences.dart';
import 'package:llmquota/services/quota_controller.dart';
import 'package:llmquota/settings_dialog.dart';

import 'widget_test.dart' as fixtures show TestWindow;

void main() {
  testWidgets(
    'live console theme changes retain Fluent controls and log state',
    (tester) async {
      final metrics = ValueNotifier<List<String>>(['Provider: Codex']);
      final logs = ValueNotifier<List<String>>(['[0.000] provider request']);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        metrics.dispose();
        logs.dispose();
      });
      Future<void> changeTheme(AppThemeMode mode) async {
        await tester.pumpWidget(
          DebugConsoleApp(
            key: const ValueKey('live-console'),
            lines: metrics,
            logLines: logs,
            themeMode: mode,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        expect(find.byType(FluentTextField), findsOneWidget);
        expect(find.byType(FluentSwitchToggle), findsOneWidget);
        expect(find.byTooltip('Clear logs'), findsOneWidget);
        final scaffoldContext = tester.element(find.byType(FluentScaffold));
        expect(
          Theme.of(scaffoldContext).brightness,
          mode == AppThemeMode.light ? Brightness.light : Brightness.dark,
        );
        if (mode == AppThemeMode.oledBlack) {
          expect(Theme.of(scaffoldContext).colorScheme.surface, Colors.black);
        }
      }

      await changeTheme(AppThemeMode.dark);
      final initialField = tester.widget<FluentTextField>(
        find.byType(FluentTextField),
      );
      await tester.tap(find.byTooltip('Pause log updates'));
      await tester.pump();
      for (final mode in [
        AppThemeMode.light,
        AppThemeMode.oledBlack,
        AppThemeMode.dark,
      ]) {
        await changeTheme(mode);
        final field = tester.widget<FluentTextField>(
          find.byType(FluentTextField),
        );
        expect(field.controller, same(initialField.controller));
        expect(find.byTooltip('Resume log updates'), findsOneWidget);
        expect(find.text('[0.000] provider request'), findsOneWidget);
      }
    },
  );

  for (final mode in AppThemeMode.values) {
    for (final size in [const Size(340, 720), const Size(1440, 900)]) {
      testWidgets('Fluent UI controls remain usable in $mode at $size', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        final controller = QuotaController()..setDemo(true);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          await tester.binding.setSurfaceSize(null);
        });
        await tester.pumpWidget(
          QuotaApp(
            controller: controller,
            window: fixtures.TestWindow(),
            preferences: OverlayPreferences(themeMode: mode),
            savePreferences: (_) async {},
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(FluentScaffold), findsOneWidget);
        expect(find.byType(FluentText), findsWidgets);
        expect(find.byType(FluentButton), findsWidgets);
        await tester.tap(find.byTooltip('Overlay settings'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        await tester.tap(find.text('Display settings'));
        await tester.pumpAndSettle();
        expect(find.byType(FluentSettingsSwitchTile), findsNWidgets(3));
        expect(find.byType(FluentSwitchToggle), findsNWidgets(3));
        expect(find.byType(Slider), findsOneWidget);
        expect(find.widgetWithText(FluentButton, 'Apply'), findsOneWidget);
        await tester.ensureVisible(find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
