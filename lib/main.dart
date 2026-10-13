import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'app_theme.dart';
import 'debug_console.dart';
import 'services/debug_console.dart';
import 'models/quota_account.dart';
import 'usage_summary.dart';
import 'window_geometry.dart';
import 'services/account_store.dart';
import 'services/preferences.dart';
import 'services/quota_controller.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  if (arguments.contains('--debug-console')) {
    final themeArgument = arguments
        .where((argument) => argument.startsWith('--theme='))
        .firstOrNull;
    final mode =
        AppThemeMode.values
            .where((mode) => mode.name == themeArgument?.substring(8))
            .firstOrNull ??
        AppThemeMode.dark;
    await runDebugConsole(initialTheme: mode);
    return;
  }
  final savedPreferences = await OverlayPreferences.load();
  final preferences = arguments.contains('--hud')
      ? savedPreferences.copyWith(hud: true)
      : savedPreferences;
  final accountStore = AccountStore();
  List<QuotaAccount> accounts;
  String? accountConfigurationError;
  try {
    accounts = await accountStore.load();
  } on Object {
    accounts = [];
    accountConfigurationError =
        'Account settings could not be loaded. Check accounts.json before saving.';
  }
  final controller = QuotaController(
    debugMode: arguments.contains('--debug'),
    accounts: accounts,
    saveAccounts: (accounts) async {
      if (accountConfigurationError != null) {
        throw StateError(accountConfigurationError);
      }
      await accountStore.save(accounts);
    },
  );
  if (arguments.contains('--demo')) controller.setDemo(true);
  final window = DesktopOverlayWindow(
    controller: controller,
    compact: preferences.compact,
    hud: preferences.hud,
    alwaysOnTop: preferences.alwaysOnTop,
    opacity: preferences.opacity,
  );
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: window.initialSize,
      minimumSize: overlayMinimumSize(window.displaySize, hud: preferences.hud),
      center: true,
      title: 'LLM Quota',
      titleBarStyle: Platform.isMacOS && !preferences.hud
          ? TitleBarStyle.normal
          : TitleBarStyle.hidden,
      windowButtonVisibility: Platform.isMacOS && !preferences.hud,
      backgroundColor: applicationTheme(
        preferences.themeMode,
      ).scaffoldBackgroundColor,
    ),
    () async {
      if (Platform.isMacOS)
        await windowManager.setBrightness(
          applicationTheme(preferences.themeMode).brightness,
        );
      await window.setAlwaysOnTop(preferences.alwaysOnTop);
      await window.setOpacity(preferences.opacity);
      await windowManager.show();
      await windowManager.focus();
    },
  );
  controller.addListener(window.updateContentSize);
  controller.start();
  runApp(
    QuotaApp(
      controller: controller,
      debugConsole: ProcessDebugConsoleWindow(),
      window: window,
      applyTheme: (mode) async {
        final theme = applicationTheme(mode);
        await windowManager.setBackgroundColor(theme.scaffoldBackgroundColor);
        if (Platform.isMacOS)
          await windowManager.setBrightness(theme.brightness);
      },
      preferences: preferences,
      accountConfigurationError: accountConfigurationError,
    ),
  );
}

class DesktopOverlayWindow implements OverlayWindow {
  DesktopOverlayWindow({
    this.controller,
    bool compact = false,
    bool hud = false,
    bool alwaysOnTop = true,
    double opacity = 1,
  }) : _compact = compact,
       _hud = hud,
       _alwaysOnTop = alwaysOnTop,
       _opacity = opacity {
    _lastContentSize = _contentSize;
  }
  final QuotaController? controller;
  bool _compact;
  bool _hud;
  bool _alwaysOnTop;
  double _opacity;
  late Size _lastContentSize;
  Future<void> _pendingResize = Future<void>.value();

  Size get displaySize {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return view.display.size / view.display.devicePixelRatio;
  }

  Size get initialSize => constrainOverlaySize(_contentSize, displaySize);

  Size get _contentSize => Size(
    _hud ? 320 : 380,
    controller == null
        ? (_hud ? 280 : (_compact ? 540 : 760))
        : overlayHeight(controller!, _compact, hud: _hud),
  );

  Future<void> _updateSize({bool force = false, bool resetWidth = false}) {
    final update = _pendingResize.then((_) async {
      final current = await windowManager.getSize();
      final content = _contentSize;
      final size = updatedOverlaySize(
        current: current,
        content: content,
        previousContent: _lastContentSize,
        display: displaySize,
        force: force,
        resetWidth: resetWidth,
      );
      _lastContentSize = content;
      await windowManager.setMinimumSize(
        overlayMinimumSize(displaySize, hud: _hud),
      );
      if ((size.width - current.width).abs() < 1 &&
          (size.height - current.height).abs() < 1)
        return;
      await windowManager.setSize(size);
    });
    _pendingResize = update.catchError((Object _) {});
    return update;
  }

  void updateContentSize() {
    if (controller == null) return;
    unawaited(_updateSize().catchError((Object _) {}));
  }

  @override
  Future<void> setAlwaysOnTop(bool enabled) async {
    _alwaysOnTop = enabled;
    await windowManager.setAlwaysOnTop(_hud || enabled);
  }

  @override
  Future<void> setOpacity(double opacity) async {
    _opacity = opacity;
    await windowManager.setOpacity(_hud ? opacity.clamp(0.45, 0.90) : opacity);
  }

  @override
  Future<void> setHud(bool enabled) async {
    if (_hud == enabled) return;
    _hud = enabled;
    await windowManager.setTitleBarStyle(
      Platform.isMacOS && !enabled
          ? TitleBarStyle.normal
          : TitleBarStyle.hidden,
      windowButtonVisibility: Platform.isMacOS && !enabled,
    );
    await windowManager.setMinimumSize(
      overlayMinimumSize(displaySize, hud: enabled),
    );
    await windowManager.setAlwaysOnTop(enabled || _alwaysOnTop);
    await windowManager.setOpacity(
      enabled ? _opacity.clamp(0.45, 0.90) : _opacity,
    );
    await _updateSize(force: true, resetWidth: true);
  }

  @override
  Future<void> setCompact(bool compact) async {
    if (_compact == compact) return;
    _compact = compact;
    await _updateSize(force: true);
  }

  @override
  Future<void> startDragging() => windowManager.startDragging();

  @override
  Future<void> close() => windowManager.close();
}

double overlayHeight(
  QuotaController controller,
  bool compact, {
  bool hud = false,
}) {
  final snapshots = controller.visibleSnapshots;
  if (hud) {
    final height =
        88 +
        snapshots.fold<double>(
          0,
          (sum, snapshot) =>
              sum +
              32 +
              (snapshot.accountLabel == null ? 0 : 20) +
              snapshot.windows.length * 46 +
              UsageSummary.estimatedHeight(snapshot, hud: true),
        );
    return height.clamp(140, 600).toDouble();
  }
  if (snapshots.isEmpty) return 320;
  final height =
      144 +
      snapshots.fold<double>(
        0,
        (sum, snapshot) =>
            sum +
            (compact ? 62 : 90) +
            (snapshot.accountLabel == null ? 0 : 22) +
            snapshot.windows.length * (compact ? 58 : 72) +
            UsageSummary.estimatedHeight(snapshot),
      );
  return height.clamp(320, 800).toDouble();
}
