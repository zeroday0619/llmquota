import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbt_fluent2_ui/gbt_fluent2_ui.dart';
import 'package:llmquota/debug_console.dart';

void main() {
  late ValueNotifier<List<String>> metrics;
  late ValueNotifier<List<String>> logs;

  setUp(() {
    metrics = ValueNotifier(['Quota used: 42%']);
    logs = ValueNotifier(['[0.001] Codex JSON-RPC send initialize']);
  });

  tearDown(() {
    metrics.dispose();
    logs.dispose();
  });

  Future<void> openConsole(
    WidgetTester tester, {
    VoidCallback? onClearLogs,
  }) async {
    await tester.pumpWidget(
      DebugConsoleApp(
        lines: metrics,
        logLines: logs,
        onClearLogs: onClearLogs,
        onRefresh: () {},
        onClose: () {},
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Live logs update independently from retained metrics', (
    tester,
  ) async {
    await openConsole(tester);
    expect(find.text(logs.value.first), findsOneWidget);
    logs.value = [...logs.value, '[0.002] Codex JSON-RPC receive initialize'];
    await tester.pumpAndSettle();
    expect(find.text(logs.value.last), findsOneWidget);

    await tester.tap(find.text('Metrics'));
    await tester.pumpAndSettle();
    expect(find.text('Quota used: 42%'), findsOneWidget);
    logs.value = [...logs.value, '[0.003] Claude file read complete'];
    await tester.pumpAndSettle();
    expect(find.text('Quota used: 42%'), findsOneWidget);
    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    expect(find.text(logs.value.last), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Pause freezes displayed logs and resume catches up', (
    tester,
  ) async {
    await openConsole(tester);
    await tester.tap(find.byTooltip('Pause log updates'));
    await tester.pumpAndSettle();
    logs.value = [...logs.value, '[0.002] Codex JSON-RPC receive result'];
    await tester.pumpAndSettle();
    expect(find.text(logs.value.last), findsNothing);
    expect(find.text(logs.value.first), findsOneWidget);
    await tester.tap(find.byTooltip('Resume log updates'));
    await tester.pumpAndSettle();
    expect(find.text(logs.value.last), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Protocol filter is case insensitive', (tester) async {
    logs.value = [
      '[0.001] Codex JSON-RPC send initialize',
      '[0.002] Antigravity HTTPS receive 200',
      '[0.003] Claude file read complete',
    ];
    await openConsole(tester);
    await tester.enterText(find.byType(TextField), 'json-rpc');
    await tester.pumpAndSettle();
    expect(find.text(logs.value.first), findsOneWidget);
    expect(find.text(logs.value[1]), findsNothing);
    expect(find.text(logs.value[2]), findsNothing);
    await tester.enterText(find.byType(TextField), 'HTTPS');
    await tester.pumpAndSettle();
    expect(find.text(logs.value.first), findsNothing);
    expect(find.text(logs.value[1]), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Clear forwards callback without changing metrics', (
    tester,
  ) async {
    var clears = 0;
    await openConsole(
      tester,
      onClearLogs: () {
        clears++;
        logs.value = [];
      },
    );
    await tester.tap(find.byTooltip('Clear logs'));
    await tester.pumpAndSettle();
    expect(clears, 1);
    expect(find.text('[0.001] Codex JSON-RPC send initialize'), findsNothing);
    await tester.tap(find.text('Metrics'));
    await tester.pumpAndSettle();
    expect(find.text('Quota used: 42%'), findsOneWidget);
    expect(metrics.value, ['Quota used: 42%']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Minimum window supports scrolling without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(340, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    logs.value = List.generate(
      500,
      (index) => '[$index] Codex JSON-RPC receive response $index',
    );
    await openConsole(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('Auto-scroll'), findsOneWidget);
    await tester.tap(find.byType(FluentSwitchToggle));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Auto-scroll follows mixed-height rows and respects manual scroll',
    (tester) async {
      tester.view.physicalSize = const Size(340, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      logs.value = List.generate(
        100,
        (index) => index.isEven
            ? '[$index] JSON-RPC send {"method":"account/rateLimits/read",'
                  '"params":{"account":"redacted","details":"${'sanitized ' * 30}"}}'
            : '[$index] JSON-RPC receive complete',
      );
      await openConsole(tester);
      expect(find.text(logs.value.last).hitTestable(), findsOneWidget);
      const appended = '[100] JSON-RPC receive appended-tail';
      logs.value = [...logs.value, appended];
      await tester.pumpAndSettle();
      expect(find.text(appended).hitTestable(), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, 160));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FluentSwitchToggle>(find.byType(FluentSwitchToggle))
            .value,
        isFalse,
      );
      const next = '[101] JSON-RPC receive unattended-tail';
      logs.value = [...logs.value, next];
      await tester.pumpAndSettle();
      expect(find.text(next).hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
