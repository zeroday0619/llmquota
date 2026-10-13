import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

Future<void> runDebugConsole() async {
  final lines = ValueNotifier<List<String>>(const ['Waiting for diagnostics…']);
  final logLines = ValueNotifier<List<String>>(const []);
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
          if (report['logLines'] is List) {
            logLines.value =
                (report['logLines'] as List).whereType<String>().toList();
          }
          final reportLines = lines.value.length;
          await WidgetsBinding.instance.endOfFrame;
          stdout.writeln(jsonEncode({
            'reportLines': reportLines,
            'renderedLogLines': logLines.value.length,
          }));
        }
      } on FormatException {
        // Invalid frames are ignored so the next complete report can render.
      }
    },
    onDone: () => exit(0),
    onError: (Object error) => exit(0),
  );
  runApp(DebugConsoleApp(lines: lines, logLines: logLines));
  await WidgetsBinding.instance.endOfFrame;
  stdout.writeln(jsonEncode({
    'consoleReady': true,
    'visible': await windowManager.isVisible(),
    'title': await windowManager.getTitle(),
  }));
}

String get _consoleFontFamily => switch (defaultTargetPlatform) {
      TargetPlatform.macOS => 'Menlo',
      TargetPlatform.windows => 'Consolas',
      TargetPlatform.linux => 'DejaVu Sans Mono',
      _ => 'monospace',
    };

class DebugConsoleApp extends StatelessWidget {
  const DebugConsoleApp({
    super.key,
    required this.lines,
    this.logLines,
    this.onRefresh,
    this.onClearLogs,
    this.onClose,
  });

  final ValueListenable<List<String>> lines;
  final ValueListenable<List<String>>? logLines;
  final VoidCallback? onRefresh;
  final VoidCallback? onClearLogs;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Debug console'),
              actions: [
                IconButton(
                  tooltip: 'Refresh providers',
                  icon: const Icon(Icons.refresh),
                  onPressed: onRefresh ??
                      () => stdout.writeln(jsonEncode({'refresh': true})),
                ),
                IconButton(
                  tooltip: 'Close console',
                  icon: const Icon(Icons.close),
                  onPressed: onClose ?? () => windowManager.close(),
                ),
              ],
              bottom:
                  const TabBar(tabs: [Tab(text: 'Logs'), Tab(text: 'Metrics')]),
            ),
            body: TabBarView(children: [
              _ConsoleLogPanel(
                lines: logLines ?? lines,
                onClear: onClearLogs ??
                    () => stdout.writeln(jsonEncode({'clearLogs': true})),
              ),
              ValueListenableBuilder<List<String>>(
                valueListenable: lines,
                builder: (context, report, child) => SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(
                    report.join('\n'),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _ConsoleLogPanel extends StatefulWidget {
  const _ConsoleLogPanel({required this.lines, required this.onClear});

  final ValueListenable<List<String>> lines;
  final VoidCallback onClear;

  @override
  State<_ConsoleLogPanel> createState() => _ConsoleLogPanelState();
}

class _ConsoleLogPanelState extends State<_ConsoleLogPanel> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _filter = TextEditingController();
  bool _paused = false;
  bool _autoScroll = true;
  List<String> _pausedLines = const [];
  String? _lastUpdate;

  @override
  void dispose() {
    _scroll.dispose();
    _filter.dispose();
    super.dispose();
  }

  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _autoScroll && !_paused && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
        valueListenable: widget.lines,
        builder: (context, liveLines, _) {
          final lines = _paused ? _pausedLines : liveLines;
          final filter = _filter.text.toLowerCase();
          final filtered = lines
              .where((line) => line.toLowerCase().contains(filter))
              .toList();
          final update = '${lines.length}:${lines.lastOrNull}:$filter';
          if (_lastUpdate != update) {
            _lastUpdate = update;
            if (_autoScroll && !_paused) _follow();
          }
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _filter,
                decoration: const InputDecoration(
                  labelText: 'Filter logs',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Expanded(
                  child: Text(
                    '${_paused ? 'Paused · ' : ''}${filtered.length} lines',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const Text('Auto-scroll', style: TextStyle(fontSize: 11)),
                Switch(
                  value: _autoScroll,
                  onChanged: (enabled) {
                    setState(() => _autoScroll = enabled);
                    if (enabled) _follow();
                  },
                ),
                IconButton(
                  tooltip: _paused ? 'Resume log updates' : 'Pause log updates',
                  icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                  onPressed: () {
                    setState(() {
                      _paused = !_paused;
                      if (_paused) _pausedLines = List.of(widget.lines.value);
                    });
                    if (!_paused) _follow();
                  },
                ),
                IconButton(
                  tooltip: 'Clear logs',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    setState(() => _pausedLines = const []);
                    widget.onClear();
                  },
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(lines.isEmpty
                          ? 'No log entries. Refresh to collect communication logs.'
                          : 'No matching log entries.'),
                    )
                  : NotificationListener<UserScrollNotification>(
                      onNotification: (notification) {
                        if (_autoScroll &&
                            _scroll.hasClients &&
                            _scroll.position.pixels <
                                _scroll.position.maxScrollExtent - 24) {
                          setState(() => _autoScroll = false);
                        }
                        return false;
                      },
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => SelectableText(
                          filtered[index],
                          style: TextStyle(
                              fontFamily: _consoleFontFamily,
                              fontSize: 12,
                              height: 1.5),
                        ),
                      ),
                    ),
            ),
          ]);
        },
      );
}
