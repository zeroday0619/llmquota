import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbt_fluent2_ui/gbt_fluent2_ui.dart';
import 'package:llmquota/app.dart';
import 'package:llmquota/debug_console.dart';
import 'package:llmquota/services/preferences.dart';
import 'package:llmquota/services/quota_controller.dart';
import 'package:llmquota/settings_dialog.dart';

import 'widget_test.dart' as fixtures show TestWindow;

void expectTheme(ThemeData theme, AppThemeMode mode) {
  expect(
    theme.brightness,
    mode == AppThemeMode.light ? Brightness.light : Brightness.dark,
  );
  if (mode == AppThemeMode.dark) {
    expect(theme.scaffoldBackgroundColor, const Color(0xff1f1f1f));
  } else if (mode == AppThemeMode.light) {
    expect(theme.scaffoldBackgroundColor, const Color(0xfffafafa));
    expect(theme.scaffoldBackgroundColor, isNot(Colors.black));
  } else {
    expect(theme.scaffoldBackgroundColor, Colors.black);
    final colors = theme.colorScheme;
    expect([
      colors.surface,
      colors.surfaceContainerLowest,
      colors.surfaceContainerLow,
      colors.surfaceContainer,
      colors.surfaceContainerHigh,
      colors.surfaceContainerHighest,
    ], everyElement(Colors.black));
    expect(colors.surfaceTint, Colors.transparent);
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    AppThemeMode mode,
    List<OverlayPreferences> saved,
  ) async {
    await tester.binding.setSurfaceSize(const Size(340, 720));
    final controller = QuotaController(accounts: []);
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
        savePreferences: (preferences) async => saved.add(preferences),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDisplay(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Overlay settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Display settings'));
    await tester.pumpAndSettle();
  }

  Future<void> selectTheme(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButtonFormField<AppThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  for (final mode in AppThemeMode.values) {
    testWidgets('overlay and settings inherit $mode', (tester) async {
      await mount(tester, mode, []);
      expectTheme(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!,
        mode,
      );
      await openDisplay(tester);
      expectTheme(
        Theme.of(tester.element(find.byType(ResponsiveSettingsSurface))),
        mode,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('debug console renders $mode', (tester) async {
      final lines = ValueNotifier<List<String>>(['[0.000] provider request']);
      addTearDown(lines.dispose);
      await tester.pumpWidget(DebugConsoleApp(lines: lines, themeMode: mode));
      await tester.pumpAndSettle();
      expectTheme(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!,
        mode,
      );
      expectTheme(Theme.of(tester.element(find.byType(FluentScaffold))), mode);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('theme applies and saves while cancel keeps the current theme', (
    tester,
  ) async {
    final saved = <OverlayPreferences>[];
    await mount(tester, AppThemeMode.dark, saved);
    await openDisplay(tester);
    await selectTheme(tester, 'Light');
    expect(saved, isEmpty);
    expectTheme(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!,
      AppThemeMode.dark,
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(saved.single.themeMode, AppThemeMode.light);
    expectTheme(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!,
      AppThemeMode.light,
    );

    await openDisplay(tester);
    await selectTheme(tester, 'OLED black');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(saved.last.themeMode, AppThemeMode.oledBlack);
    expectTheme(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!,
      AppThemeMode.oledBlack,
    );

    await openDisplay(tester);
    await selectTheme(tester, 'Dark');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saved, hasLength(2));
    expectTheme(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!,
      AppThemeMode.oledBlack,
    );
    expect(tester.takeException(), isNull);
  });
}
