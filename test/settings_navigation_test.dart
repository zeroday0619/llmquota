import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/app.dart';
import 'package:llmquota/about_dialog.dart';
import 'package:llmquota/services/preferences.dart';
import 'package:llmquota/services/quota_controller.dart';

import 'widget_test.dart' as fixtures show TestWindow;

class SettingsTestWindow extends fixtures.TestWindow {
  final compactValues = <bool>[];
  final opacityValues = <double>[];
  final topValues = <bool>[];

  @override
  Future<void> setCompact(bool compact) async => compactValues.add(compact);
  @override
  Future<void> setOpacity(double opacity) async => opacityValues.add(opacity);
  @override
  Future<void> setAlwaysOnTop(bool enabled) async => topValues.add(enabled);
}

void main() {
  testWidgets('settings hub opens app information and returns to overlay', (
    tester,
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
        preferences: const OverlayPreferences(),
        savePreferences: (_) async {},
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Overlay settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('About llmquota'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About llmquota'));
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationInfoDialog), findsOneWidget);
    expect(find.text('Developer: zeroday0619'), findsOneWidget);
    expect(find.text('Application license'), findsOneWidget);
    expect(find.text('Open-source notices'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationInfoDialog), findsNothing);
    expect(find.byTooltip('Overlay settings').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft,
  ]) {
    testWidgets('settings shortcut opens categories using $modifier', (
      tester,
    ) async {
      final controller = QuotaController(accounts: []);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
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
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(find.text('Display settings'), findsOneWidget);
      expect(find.text('Debug settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'display changes apply together and cancel preserves preferences',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(340, 720));
      final controller = QuotaController(accounts: []);
      final window = SettingsTestWindow();
      final saved = <OverlayPreferences>[];
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        QuotaApp(
          controller: controller,
          window: window,
          preferences: const OverlayPreferences(),
          savePreferences: (preferences) async => saved.add(preferences),
        ),
      );

      Future<void> openDisplay() async {
        await tester.tap(find.byTooltip('Overlay settings'));
        await tester.pumpAndSettle();
        expect(find.text('Display settings'), findsOneWidget);
        expect(find.text('Debug settings'), findsOneWidget);
        await tester.tap(find.text('Display settings'));
        await tester.pumpAndSettle();
      }

      await openDisplay();
      await tester.tap(find.text('Compact view'));
      await tester.tap(find.text('Keep on top'));
      await tester.drag(find.byType(Slider), const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(window.compactValues, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(window.opacityValues, isEmpty);

      await openDisplay();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 1);
      await tester.tap(find.text('Compact view'));
      await tester.tap(find.text('Keep on top'));
      await tester.drag(find.byType(Slider), const Offset(-80, 0));
      await tester.pumpAndSettle();
      final selectedOpacity = tester.widget<Slider>(find.byType(Slider)).value;
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(saved, hasLength(1));
      expect(saved.single.compact, isTrue);
      expect(saved.single.alwaysOnTop, isFalse);
      expect(saved.single.opacity, selectedOpacity);
      expect(window.compactValues, [true]);
      expect(window.topValues, [false]);
      expect(window.opacityValues, [selectedOpacity]);
      expect(tester.takeException(), isNull);
    },
  );
}
