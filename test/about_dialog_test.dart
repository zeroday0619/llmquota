import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmquota/app_theme.dart';
import 'package:llmquota/services/preferences.dart';
import 'package:llmquota/about_dialog.dart';

class _InfoAssets extends CachingAssetBundle {
  _InfoAssets({this.fail = false});
  final bool fail;

  @override
  Future<ByteData> load(String key) async {
    if (fail) throw StateError('Missing asset');
    final content = key == 'pubspec.yaml'
        ? 'name: llmquota\nversion: 0.1.0+1\n'
        : 'This is free and unencumbered software released into the public domain.\nEND OF LICENSE';
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
  }
}

Future<void> _open(
  WidgetTester tester, {
  bool fail = false,
  String buildName = '',
  String buildNumber = '',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: applicationTheme(AppThemeMode.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ApplicationInfoDialog(
                assetBundle: _InfoAssets(fail: fail),
                buildName: buildName,
                buildNumber: buildNumber,
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
  testWidgets('compiled build version takes precedence over manifest', (
    tester,
  ) async {
    await _open(tester, fail: true, buildName: '2.3.4', buildNumber: '12');
    expect(find.text('Version: 2.3.4+12'), findsOneWidget);
  });

  testWidgets('shows developer and manifest version with build number', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('Developer: zeroday0619'), findsOneWidget);
    expect(find.text('Version: 0.1.0+1'), findsOneWidget);
  });

  testWidgets('license opens a separate UI with complete asset text', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('Application license'));
    await tester.pumpAndSettle();
    expect(find.textContaining('END OF LICENSE'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('App information'), findsOneWidget);
  });

  testWidgets('dependency notices open separate list and license detail', (
    tester,
  ) async {
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks([
        'test_dependency',
      ], 'Dependency notice text.');
    });
    await _open(tester);
    await tester.tap(find.text('Open-source notices'));
    await tester.pumpAndSettle();
    expect(find.text('Open-source notices'), findsWidgets);
    expect(find.byType(Dialog), findsNWidgets(2));
    await tester.tap(find.text('test_dependency'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dependency notice text.'), findsWidgets);
  });

  testWidgets('missing assets show unavailable state and license error', (
    tester,
  ) async {
    await _open(tester, fail: true);
    expect(find.text('Version: Unavailable'), findsOneWidget);
    await tester.tap(find.text('Application license'));
    await tester.pumpAndSettle();
    expect(
      find.text('Application license could not be loaded.'),
      findsOneWidget,
    );
  });

  testWidgets('information fits a small window with scrolling', (tester) async {
    tester.view.physicalSize = const Size(340, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(tester);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Open-source notices'),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Open-source notices'), findsOneWidget);
  });
}
