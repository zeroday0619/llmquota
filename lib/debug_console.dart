import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

Future<void> runDebugConsole() async {
  final lines = ValueNotifier<List<String>>(const ['Waiting for diagnostics…']);
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(800, 640),
      minimumSize: Size(340, 260),
      center: true,
      title: 'LLM Quota — Debug console',
      backgroundColor: Color(0xff11151c),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) async {
      try {
        final report = jsonDecode(line);
        if (report is Map && report['activate'] == true) {
          await windowManager.restore();
          await windowManager.show();
          await windowManager.focus();
        }
        if (report is Map && report['lines'] is List) {
          lines.value = (report['lines'] as List).whereType<String>().toList();
          final reportLines = lines.value.length;
          await WidgetsBinding.instance.endOfFrame;
          stdout.writeln(jsonEncode({'reportLines': reportLines}));
        }
      } on FormatException {
        // Invalid frames are ignored so the next complete report can render.
      }
    },
    onDone: () => exit(0),
    onError: (Object error) => exit(0),
  );
  runApp(DebugConsoleApp(lines: lines));
  await WidgetsBinding.instance.endOfFrame;
  stdout.writeln(jsonEncode({
    'consoleReady': true,
    'visible': await windowManager.isVisible(),
    'title': await windowManager.getTitle(),
  }));
}

class DebugConsoleApp extends StatelessWidget {
  const DebugConsoleApp({super.key, required this.lines});

  final ValueListenable<List<String>> lines;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Debug console'),
            actions: [
              IconButton(
                tooltip: 'Refresh providers',
                icon: const Icon(Icons.refresh),
                onPressed: () => stdout.writeln(jsonEncode({'refresh': true})),
              ),
              IconButton(
                tooltip: 'Close console',
                icon: const Icon(Icons.close),
                onPressed: () => windowManager.close(),
              ),
            ],
          ),
          body: ValueListenableBuilder<List<String>>(
            valueListenable: lines,
            builder: (context, report, child) => SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                report.join('\n'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
        ),
      );
}
