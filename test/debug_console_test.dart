import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/debug_console.dart';

void main() {
  testWidgets('Console renders updated reports and exposes controls',
      (tester) async {
    final lines = ValueNotifier<List<String>>(['First report']);
    await tester.pumpWidget(DebugConsoleApp(lines: lines));
    expect(find.text('First report'), findsOneWidget);
    expect(find.byTooltip('Refresh providers'), findsOneWidget);
    expect(find.byTooltip('Close console'), findsOneWidget);
    lines.value = ['Provider: Codex', 'Token total: Unavailable'];
    await tester.pump();
    expect(find.text('First report'), findsNothing);
    expect(find.text('Provider: Codex\nToken total: Unavailable'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    lines.dispose();
  });
}
