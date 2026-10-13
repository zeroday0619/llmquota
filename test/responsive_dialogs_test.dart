import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/app_theme.dart';
import 'package:llmquota/about_dialog.dart';
import 'package:llmquota/account_dialog.dart';
import 'package:llmquota/models/quota.dart';
import 'package:llmquota/models/quota_account.dart';
import 'package:llmquota/services/preferences.dart';
import 'package:llmquota/services/quota_controller.dart';
import 'package:llmquota/settings_dialog.dart';

void main() {
  for (final size in [
    const Size(320, 240),
    const Size(640, 480),
    const Size(1920, 1080),
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('dialogs remain usable at $size with text scale $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = QuotaController(accounts: []);
        addTearDown(controller.dispose);
        final populatedController = QuotaController(
          accounts: const [
            QuotaAccount(
              id: 'codex',
              provider: ProviderKind.codex,
              label: 'Development account with a long descriptive profile name',
            ),
          ],
        );
        addTearDown(populatedController.dispose);
        for (final dialog in <Widget>[
          const SettingsDialog(),
          const DisplaySettingsDialog(preferences: OverlayPreferences()),
          DiagnosticsSettingsDialog(
            controller: controller,
            onOpenConsole: () {},
          ),
          AccountManagerDialog(controller: controller),
          AccountManagerDialog(controller: populatedController),
          const ApplicationInfoDialog(buildName: '1.0.0'),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: applicationTheme(AppThemeMode.dark),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => dialog,
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${dialog.runtimeType}',
          );
          if (dialog is AccountManagerDialog) {
            await tester.ensureVisible(find.text('Add account'));
            await tester.tap(find.text('Add account'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(find.text('Save'));
            await tester.tap(find.text('Save'));
            await tester.pumpAndSettle();
            expect(find.text('Enter an account label.'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(find.text('Cancel'));
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
          }
          final closing = dialog is DisplaySettingsDialog
              ? find.text('Cancel')
              : find.text('Done');
          await tester.ensureVisible(closing);
          await tester.pumpAndSettle();
          await tester.tap(closing);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
