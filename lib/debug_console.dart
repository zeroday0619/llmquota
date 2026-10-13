import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gbt_fluent2_ui/gbt_fluent2_ui.dart';
import 'package:gbt_fluent2_ui/fluent_icons.dart';
import 'package:window_manager/window_manager.dart';

import 'app_theme.dart';
import 'fluent_controls.dart';
import 'window_geometry.dart';
import 'services/preferences.dart';

Future<void> runDebugConsole({
  AppThemeMode initialTheme = AppThemeMode.dark,
}) async {
  final themeMode = ValueNotifier(initialTheme);
  final lines = ValueNotifier<List<String>>(const ['Waiting for diagnostics…']);
  final logLines = ValueNotifier<List<String>>(const []);
  final display =
      WidgetsBinding.instance.platformDispatcher.views.first.display;
  final displaySize = display.size / display.devicePixelRatio;
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: constrainOverlaySize(const Size(800, 640), displaySize),
      minimumSize: overlayMinimumSize(displaySize, hud: false),
      center: true,
      title: 'LLM Quota — Debug console',
      backgroundColor: applicationTheme(initialTheme).scaffoldBackgroundColor,
    ),
    () async {
      if (Platform.isMacOS)
        await windowManager.setBrightness(
          applicationTheme(initialTheme).brightness,
        );
      await windowManager.show();
      await windowManager.focus();
    },
  );
  stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(
        (line) async {
          try {
            final report = jsonDecode(line);
            if (report is Map && report['themeMode'] is String) {
              final mode = AppThemeMode.values
                  .where((mode) => mode.name == report['themeMode'])
                  .firstOrNull;
              if (mode != null && mode != themeMode.value) {
                themeMode.value = mode;
                await windowManager.setBackgroundColor(
                  applicationTheme(mode).scaffoldBackgroundColor,
                );
                if (Platform.isMacOS)
                  await windowManager.setBrightness(
                    applicationTheme(mode).brightness,
                  );
              }
            }
            if (report is Map && report['activate'] == true) {
              await windowManager.restore();
              await windowManager.show();
              await windowManager.focus();
            }
            if (report is Map && report['lines'] is List) {
              lines.value = (report['lines'] as List)
                  .whereType<String>()
                  .toList();
              if (report['logLines'] is List) {
                logLines.value = (report['logLines'] as List)
                    .whereType<String>()
                    .toList();
              }
              final reportLines = lines.value.length;
              await WidgetsBinding.instance.endOfFrame;
              stdout.writeln(
                jsonEncode({
                  'reportLines': reportLines,
                  'renderedLogLines': logLines.value.length,
                }),
              );
            }
          } on FormatException {
            // Invalid frames are ignored so the next complete report can render.
          }
        },
        onDone: () => exit(0),
        onError: (Object error) => exit(0),
      );
  runApp(
    ValueListenableBuilder<AppThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) =>
          DebugConsoleApp(lines: lines, logLines: logLines, themeMode: mode),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  stdout.writeln(
    jsonEncode({
      'consoleReady': true,
      'visible': await windowManager.isVisible(),
      'title': await windowManager.getTitle(),
    }),
  );
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
    this.themeMode = AppThemeMode.dark,
  });

  final ValueListenable<List<String>> lines;
  final ValueListenable<List<String>>? logLines;
  final VoidCallback? onRefresh;
  final VoidCallback? onClearLogs;
  final VoidCallback? onClose;
  final AppThemeMode themeMode;

  @override
  Widget build(BuildContext context) => FluentProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: Duration.zero,
      theme: applicationTheme(themeMode),
      home: DefaultTabController(
        length: 2,
        child: FluentScaffold(
          appBar: FluentNavBar(
            backgroundColor: applicationTheme(themeMode).colorScheme.surface,
            foregroundColor: applicationTheme(themeMode).colorScheme.onSurface,
            title: NavLeftTitle(title: 'Debug console'),
            actions: [
              FluentActionButton(
                tooltip: 'Refresh providers',
                icon: const Icon(FluentIcons.arrow_sync_20_regular),
                onPressed:
                    onRefresh ??
                    () => stdout.writeln(jsonEncode({'refresh': true})),
              ),
              FluentActionButton(
                tooltip: 'Close console',
                icon: const Icon(FluentIcons.dismiss_20_regular),
                onPressed: onClose ?? () => windowManager.close(),
              ),
            ],
            childPadding: EdgeInsets.zero,
            child: const TabBar(
              tabs: [
                Tab(text: 'Logs'),
                Tab(text: 'Metrics'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _ConsoleLogPanel(
                lines: logLines ?? lines,
                onClear:
                    onClearLogs ??
                    () => stdout.writeln(jsonEncode({'clearLogs': true})),
              ),
              ValueListenableBuilder<List<String>>(
                valueListenable: lines,
                builder: (context, report, child) => SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(
                    report.join('\n'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: _consoleFontFamily,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
  final FluentTextFieldController _filter = FluentTextFieldController();
  bool _paused = false;
  bool _autoScroll = true;
  List<String> _pausedLines = const [];
  String? _lastUpdate;

  @override
  void dispose() {
    _scroll.dispose();
    _filter.dispose();
    _filter.hasFocus.dispose();
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
      final filter = _filter.textEditingController.text.toLowerCase();
      final filtered = lines
          .where((line) => line.toLowerCase().contains(filter))
          .toList();
      final update = '${lines.length}:${lines.lastOrNull}:$filter';
      if (_lastUpdate != update) {
        _lastUpdate = update;
        if (_autoScroll && !_paused) _follow();
      }
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FluentTextField(
              controller: _filter,
              label: 'Filter logs',
              prefixIcon: const Icon(FluentIcons.search_20_regular, size: 20),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    '${_paused ? 'Paused · ' : ''}${filtered.length} lines',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Auto-scroll',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  FluentSwitchToggle(
                    value: _autoScroll,
                    onChanged: (enabled) {
                      setState(() => _autoScroll = enabled);
                      if (enabled) _follow();
                    },
                  ),
                  FluentActionButton(
                    tooltip: _paused
                        ? 'Resume log updates'
                        : 'Pause log updates',
                    icon: Icon(
                      _paused
                          ? FluentIcons.play_20_regular
                          : FluentIcons.pause_20_regular,
                    ),
                    onPressed: () {
                      setState(() {
                        _paused = !_paused;
                        if (_paused) _pausedLines = List.of(widget.lines.value);
                      });
                      if (!_paused) _follow();
                    },
                  ),
                  FluentActionButton(
                    tooltip: 'Clear logs',
                    icon: const Icon(FluentIcons.delete_20_regular),
                    onPressed: () {
                      setState(() => _pausedLines = const []);
                      widget.onClear();
                    },
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        lines.isEmpty
                            ? 'No log entries. Refresh to collect communication logs.'
                            : 'No matching log entries.',
                        textAlign: TextAlign.center,
                      ),
                    ),
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
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}
