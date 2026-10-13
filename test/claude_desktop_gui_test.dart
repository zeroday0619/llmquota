import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/app.dart';
import 'package:llmquota/settings_dialog.dart';
import 'package:llmquota/services/preferences.dart';
import 'package:llmquota/services/quota_controller.dart';
import 'widget_test.dart' as fixtures;

void main() {
  testWidgets(
    'Desktop access is explicit and connection feedback stays in the dialog',
    (tester) async {
      var requested = 0;
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
          requestClaudeDesktopAccess: () async {
            requested++;
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(requested, 0);
      await tester.tap(find.byTooltip('Overlay settings'));
      await tester.pumpAndSettle();
      final providers = find.descendant(
        of: find.byType(SettingsDialog),
        matching: find.text('Connect providers'),
      );
      await tester.ensureVisible(providers);
      await tester.tap(providers);
      await tester.pumpAndSettle();
      final connect = find.text('Connect Claude Desktop');
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await tester.pumpAndSettle();
      expect(requested, 1);
      expect(
        find.text('Sign in to Claude Desktop before connecting.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
