import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/app_theme.dart';
import 'package:gbt_fluent2_ui/gbt_fluent2_ui.dart';
import 'package:llmquota/services/preferences.dart';
import 'package:llmquota/services/quota_controller.dart';
import 'package:llmquota/settings_dialog.dart';

Future<void> openDialog(
  WidgetTester tester,
  Widget dialog,
  ValueChanged<Object?> onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: applicationTheme(AppThemeMode.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => onResult(
              await showDialog<Object>(
                context: context,
                builder: (_) => dialog,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('display settings apply draft changes together', (tester) async {
    Object? result;
    await openDialog(
      tester,
      const DisplaySettingsDialog(preferences: OverlayPreferences()),
      (value) => result = value,
    );
    await tester.tap(find.text('HUD mode'));
    await tester.tap(find.text('Compact view'));
    await tester.tap(find.text('Keep on top'));
    await tester.tap(find.byType(DropdownButtonFormField<AppThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OLED black').last);
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(0.65);
    await tester.pump();
    expect(find.text('Opacity: 65%'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final preferences = result as OverlayPreferences;
    expect(preferences.hud, isTrue);
    expect(preferences.compact, isTrue);
    expect(preferences.alwaysOnTop, isFalse);
    expect(preferences.opacity, 0.65);
    expect(preferences.themeMode, AppThemeMode.oledBlack);
  });

  testWidgets('cancel does not return draft changes', (tester) async {
    Object? result = 'pending';
    await openDialog(
      tester,
      const DisplaySettingsDialog(preferences: OverlayPreferences()),
      (value) => result = value,
    );
    await tester.tap(find.text('HUD mode'));
    await tester.tap(find.byType(DropdownButtonFormField<AppThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('restore defaults requires apply', (tester) async {
    Object? result;
    await openDialog(
      tester,
      const DisplaySettingsDialog(
        preferences: OverlayPreferences(
          hud: true,
          compact: true,
          alwaysOnTop: false,
          opacity: 0.45,
          themeMode: AppThemeMode.light,
        ),
      ),
      (value) => result = value,
    );
    await tester.tap(find.text('Restore defaults'));
    await tester.pump();
    expect(result, isNull);
    expect(find.text('Opacity: 100%'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final preferences = result as OverlayPreferences;
    expect(preferences.hud, isFalse);
    expect(preferences.compact, isFalse);
    expect(preferences.alwaysOnTop, isTrue);
    expect(preferences.opacity, 1);
    expect(preferences.themeMode, AppThemeMode.dark);
  });

  testWidgets('debug controls track session state', (tester) async {
    final controller = QuotaController();
    addTearDown(controller.dispose);
    var opened = false;
    await openDialog(
      tester,
      DiagnosticsSettingsDialog(
        controller: controller,
        onOpenConsole: () => opened = true,
      ),
      (_) {},
    );
    expect(
      tester
          .widget<FluentButton>(
            find.widgetWithText(FluentButton, 'Open debug console'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Debug mode'));
    await tester.pump();
    expect(controller.debugMode, isTrue);
    await tester.tap(find.text('Open debug console'));
    expect(opened, isTrue);
    await tester.tap(find.text('Demo data'));
    await tester.pump();
    expect(controller.demo, isTrue);
    await tester.tap(find.text('Debug mode'));
    await tester.pump();
    expect(controller.debugMode, isFalse);
  });

  testWidgets('display settings scroll on a small overlay', (tester) async {
    await tester.binding.setSurfaceSize(const Size(340, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openDialog(
      tester,
      const DisplaySettingsDialog(preferences: OverlayPreferences()),
      (_) {},
    );
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Apply'), findsOneWidget);
  });
}
