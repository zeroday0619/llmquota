import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/app_theme.dart';
import 'package:llmquota/fluent_controls.dart';
import 'package:llmquota/services/preferences.dart';

double contrast(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance < backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final mode in AppThemeMode.values) {
    test('$mode maintains readable Fluent foregrounds', () {
      final colors = applicationTheme(mode).colorScheme;
      expect(
        contrast(colors.onSurface, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.onSurfaceVariant, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.primary, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      if (mode == AppThemeMode.oledBlack) {
        expect(colors.surface, Colors.black);
        expect(colors.outlineVariant, isNot(Colors.black));
      }
    });
  }

  test('macOS uses the native Fluent typography scale', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final text = applicationTheme(AppThemeMode.light).textTheme;
    expect(text.bodyMedium!.fontFamily, '.AppleSystemUIFont');
    expect(text.bodyMedium!.fontSize, 13);
    expect(text.labelSmall!.fontSize, 10);
    expect(text.titleLarge!.fontSize, 17);
  });

  test('Windows uses Segoe UI and the Fluent desktop typography scale', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final text = applicationTheme(AppThemeMode.light).textTheme;
    expect(text.bodyMedium!.fontFamily, 'Segoe UI');
    expect(text.bodyMedium!.fontSize, 14);
    expect(text.labelSmall!.fontSize, 12);
    expect(text.titleLarge!.fontSize, 20);
  });

  test('Linux retains a portable system font', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final text = applicationTheme(AppThemeMode.light).textTheme;
    expect(text.bodyMedium!.fontFamily, 'sans-serif');
    expect(text.bodyMedium!.fontSize, 14);
  });

  testWidgets('toolbar action retains its target and regular icon size', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: applicationTheme(AppThemeMode.light),
        home: Scaffold(
          body: FluentActionButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => activations++,
            tooltip: 'Settings',
          ),
        ),
      ),
    );
    final button = find.byType(FluentActionButton);
    expect(tester.getSize(button), const Size(36, 36));
    final icon = tester.widget<Icon>(
      find.descendant(of: button, matching: find.byType(Icon)),
    );
    expect(icon.size, 20);
    await tester.tap(button);
    expect(activations, 1);
  });
}
