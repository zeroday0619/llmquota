import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../debug_report.dart';
import 'quota_controller.dart';
import 'preferences.dart';

abstract class DebugConsoleWindow {
  Future<void> show(QuotaController controller);
  Future<void> close();
}

void setDebugConsoleTheme(DebugConsoleWindow? console, AppThemeMode mode) {
  if (console is ProcessDebugConsoleWindow) console.setThemeMode(mode);
}

class ProcessDebugConsoleWindow implements DebugConsoleWindow {
  AppThemeMode _themeMode = AppThemeMode.dark;

  void setThemeMode(AppThemeMode mode) {
    _themeMode = mode;
    _sendReport();
  }

  Process? _process;
  QuotaController? _controller;
  Timer? _timer;
  Timer? _pendingReport;
  Future<void>? _opening;
  int _generation = 0;

  @override
  Future<void> show(QuotaController controller) async {
    if (_opening != null) return _opening;
    if (_process != null) {
      _process!.stdin.writeln(jsonEncode({'activate': true}));
      return;
    }
    final generation = _generation;
    final opening = _open(controller, generation);
    _opening = opening;
    try {
      await opening;
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  Future<void> _open(QuotaController controller, int generation) async {
    final process = await Process.start(Platform.resolvedExecutable, [
      '--debug-console',
      '--theme=${_themeMode.name}',
    ]);
    if (generation != _generation) {
      process.kill();
      return;
    }
    final ready = Completer<void>();
    _process = process;
    _controller = controller;
    controller.addListener(_queueReport);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            try {
              final request = jsonDecode(line);
              if (request is Map &&
                  request['consoleReady'] == true &&
                  request['visible'] == true &&
                  request['title'] == 'LLM Quota — Debug console' &&
                  !ready.isCompleted) {
                ready.complete();
              }
              if (request is Map &&
                  request['clearLogs'] == true &&
                  identical(_process, process)) {
                controller.clearDebugLogs();
              }
              if (request is Map &&
                  request['refresh'] == true &&
                  identical(_process, process)) {
                unawaited(controller.refresh());
              }
            } on FormatException {
              // Native runtime messages do not belong to the console protocol.
            }
          },
          onError: (Object error) {
            if (!ready.isCompleted) {
              ready.completeError(StateError('Debug console protocol failed.'));
            }
          },
        );
    unawaited(process.stderr.drain<void>());
    unawaited(
      process.stdin.done.catchError((Object error) {
        if (identical(_process, process)) unawaited(close());
      }),
    );
    unawaited(
      process.exitCode.then((_) {
        if (!ready.isCompleted) {
          if (generation != _generation) {
            ready.complete();
          } else {
            ready.completeError(
              StateError('Debug console exited before opening.'),
            );
          }
        }
        if (identical(_process, process)) _detach();
      }),
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sendReport());
    _sendReport();
    try {
      await ready.future.timeout(const Duration(seconds: 15));
    } on Object {
      if (identical(_process, process)) _detach();
      process.kill();
      await process.exitCode;
      rethrow;
    }
  }

  void _queueReport() {
    if (_process == null || _pendingReport != null) return;
    // Coalescing notifications keeps bursty provider traffic from flooding IPC.
    _pendingReport = Timer(const Duration(milliseconds: 100), () {
      _pendingReport = null;
      _sendReport();
    });
  }

  void _sendReport() {
    _pendingReport?.cancel();
    _pendingReport = null;
    final process = _process;
    final controller = _controller;
    if (process == null || controller == null) return;
    try {
      process.stdin.writeln(
        jsonEncode({
          'themeMode': _themeMode.name,
          'lines': buildDebugReport(controller, DateTime.now()),
          'logLines': buildDebugLogLines(controller),
        }),
      );
    } on Object {
      // The child may close between the exit notification and a report update.
      unawaited(close());
    }
  }

  void _detach() {
    _pendingReport?.cancel();
    _pendingReport = null;
    _timer?.cancel();
    _timer = null;
    _controller?.removeListener(_queueReport);
    _controller = null;
    _process = null;
  }

  @override
  Future<void> close() async {
    _generation++;
    final process = _process;
    _detach();
    if (process != null) {
      process.kill();
      await process.exitCode;
    }
    try {
      await _opening;
    } on Object {
      // The show caller owns startup failures; closing only releases resources.
    }
  }
}
