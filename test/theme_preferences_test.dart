import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/services/preferences.dart';

void main() {
  test('legacy preferences retain the original dark appearance', () {
    final preferences = OverlayPreferences.fromJson({
      'alwaysOnTop': false,
      'compact': true,
      'hud': true,
      'opacity': 0.7,
    });
    expect(preferences.themeMode, AppThemeMode.dark);
    expect(preferences.alwaysOnTop, isFalse);
    expect(preferences.compact, isTrue);
    expect(preferences.hud, isTrue);
    expect(preferences.opacity, 0.7);
  });

  test('invalid stored theme values fall back to dark', () {
    for (final value in [null, 'system', '', 42, false, <String>[]]) {
      expect(
        OverlayPreferences.fromJson({'themeMode': value}).themeMode,
        AppThemeMode.dark,
      );
    }
  });

  test('all appearance modes survive the saved JSON representation', () {
    for (final mode in AppThemeMode.values) {
      final preferences = OverlayPreferences(
        themeMode: mode,
        compact: true,
        opacity: 0.65,
      );
      final stored =
          jsonDecode(jsonEncode(preferences.toJson())) as Map<String, dynamic>;
      final restored = OverlayPreferences.fromJson(stored);
      expect(stored['themeMode'], mode.name);
      expect(restored.themeMode, mode);
      expect(restored.compact, isTrue);
      expect(restored.opacity, 0.65);
    }
  });

  test('unrelated preference edits preserve the selected appearance', () {
    const preferences = OverlayPreferences(themeMode: AppThemeMode.oledBlack);
    expect(
      preferences.copyWith(compact: true).themeMode,
      AppThemeMode.oledBlack,
    );
    final changed = preferences.copyWith(themeMode: AppThemeMode.light);
    expect(changed.themeMode, AppThemeMode.light);
    expect(changed.alwaysOnTop, preferences.alwaysOnTop);
    expect(changed.opacity, preferences.opacity);
  });
}
