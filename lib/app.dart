import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gbt_fluent2_ui/gbt_fluent2_ui.dart';
import 'package:gbt_fluent2_ui/fluent_icons.dart';
import 'fluent_controls.dart';
import 'package:flutter/services.dart';

import 'models/quota.dart';
import 'app_theme.dart';
import 'account_dialog.dart';
import 'debug_dialog.dart';
import 'services/debug_console.dart';
import 'services/preferences.dart';
import 'settings_dialog.dart';
import 'about_dialog.dart';
import 'services/quota_controller.dart';
import 'services/quota_sources.dart';
import 'services/claude_desktop.dart';
import 'hud_overlay.dart';
import 'usage_summary.dart';

abstract class OverlayWindow {
  Future<void> setHud(bool enabled);
  Future<void> setAlwaysOnTop(bool enabled);
  Future<void> setOpacity(double opacity);
  Future<void> setCompact(bool compact);
  Future<void> startDragging();
  Future<void> close();
}

class QuotaApp extends StatefulWidget {
  const QuotaApp({
    super.key,
    required this.controller,
    required this.window,
    required this.preferences,
    this.savePreferences,
    this.applyTheme,
    this.requestClaudeDesktopAccess,
    this.accountConfigurationError,
    this.debugConsole,
  });
  final DebugConsoleWindow? debugConsole;
  final String? accountConfigurationError;
  final QuotaController controller;
  final OverlayWindow window;
  final OverlayPreferences preferences;
  final Future<void> Function(OverlayPreferences)? savePreferences;
  final Future<void> Function(AppThemeMode)? applyTheme;
  final Future<bool> Function()? requestClaudeDesktopAccess;

  @override
  State<QuotaApp> createState() => _QuotaAppState();
}

class _QuotaAppState extends State<QuotaApp> {
  late AppThemeMode _themeMode = widget.preferences.themeMode;

  @override
  Widget build(BuildContext context) => FluentProvider(
    child: MaterialApp(
      title: 'LLM Quota',
      themeAnimationDuration: Duration.zero,
      debugShowCheckedModeBanner: false,
      theme: applicationTheme(_themeMode),
      home: OverlayPage(
        controller: widget.controller,
        window: widget.window,
        preferences: widget.preferences,
        savePreferences: widget.savePreferences,
        applyTheme: widget.applyTheme,
        requestClaudeDesktopAccess: widget.requestClaudeDesktopAccess,
        onThemeChanged: (mode) => setState(() => _themeMode = mode),
        accountConfigurationError: widget.accountConfigurationError,
        debugConsole: widget.debugConsole,
      ),
    ),
  );
}

class OverlayPage extends StatefulWidget {
  const OverlayPage({
    super.key,
    required this.controller,
    required this.window,
    required this.preferences,
    this.savePreferences,
    this.applyTheme,
    this.requestClaudeDesktopAccess,
    this.onThemeChanged,
    this.accountConfigurationError,
    this.debugConsole,
  });
  final DebugConsoleWindow? debugConsole;
  final String? accountConfigurationError;
  final QuotaController controller;
  final OverlayWindow window;
  final OverlayPreferences preferences;
  final Future<void> Function(OverlayPreferences)? savePreferences;
  final Future<void> Function(AppThemeMode)? applyTheme;
  final Future<bool> Function()? requestClaudeDesktopAccess;
  final ValueChanged<AppThemeMode>? onThemeChanged;

  @override
  State<OverlayPage> createState() => _OverlayPageState();
}

class _OverlayPageState extends State<OverlayPage> {
  late OverlayPreferences preferences = widget.preferences;
  late final Timer ticker;
  bool applyingPreferences = false;
  bool _observedDebugMode = false;
  bool _settingsOpen = false;
  DialogRoute<void>? _debugRoute;

  void _synchronizeDebugConsole() {
    final enabled = widget.controller.debugMode;
    if (enabled == _observedDebugMode) return;
    _observedDebugMode = enabled;
    if (enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.controller.debugMode) {
          unawaited(_showDebugConsole());
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    } else {
      unawaited(widget.debugConsole?.close() ?? Future<void>.value());
      final route = _debugRoute;
      if (route != null && route.isActive) {
        route.navigator?.removeRoute(route);
      }
      _debugRoute = null;
    }
  }

  Future<void> _showDebugConsole() async {
    if (!mounted || !widget.controller.debugMode) return;
    try {
      final console = widget.debugConsole;
      if (console != null) {
        await console.show(widget.controller);
      } else if (_debugRoute == null) {
        final route = DialogRoute<void>(
          context: context,
          builder: (_) => DebugDialog(controller: widget.controller),
        );
        _debugRoute = route;
        await Navigator.of(context).push(route);
        if (_debugRoute == route) _debugRoute = null;
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the debug console. Retry from settings.',
            ),
          ),
        );
      }
    }
  }

  Future<String> _connectClaudeDesktop() async {
    final connected =
        await (widget.requestClaudeDesktopAccess?.call() ??
            QuotaSources.desktopService.requestAccess());
    if (!connected) return 'Sign in to Claude Desktop before connecting.';
    await widget.controller.refresh();
    final snapshot = widget.controller.snapshots['claude'];
    if (snapshot?.source == 'Claude Desktop' && snapshot!.hasUsage) {
      return snapshot.status == QuotaStatus.stale
          ? snapshot.message ?? 'Claude Desktop usage is temporarily stale.'
          : 'Claude Desktop usage loaded.';
    }
    return snapshot?.message ??
        'Desktop access granted. Usage is currently coming from the Claude Code bridge.';
  }

  Future<void> _openSettings() async {
    if (!mounted || _settingsOpen || applyingPreferences) return;
    setState(() => _settingsOpen = true);
    try {
      final section = await showDialog<SettingsSection>(
        context: context,
        builder: (_) => const SettingsDialog(),
      );
      if (!mounted || section == null) return;
      switch (section) {
        case SettingsSection.display:
          final next = await showDialog<OverlayPreferences>(
            context: context,
            builder: (_) => DisplaySettingsDialog(preferences: preferences),
          );
          if (mounted && next != null) await update(next);
        case SettingsSection.accounts:
          await showDialog<void>(
            context: context,
            builder: (_) => AccountManagerDialog(
              controller: widget.controller,
              configurationError: widget.accountConfigurationError,
            ),
          );
        case SettingsSection.connections:
          await showDialog<void>(
            context: context,
            builder: (_) =>
                _ConnectionHelp(onConnectDesktop: _connectClaudeDesktop),
          );
        case SettingsSection.diagnostics:
          await showDialog<void>(
            context: context,
            builder: (_) => DiagnosticsSettingsDialog(
              controller: widget.controller,
              onOpenConsole: () => unawaited(_showDebugConsole()),
            ),
          );
        case SettingsSection.about:
          await showDialog<void>(
            context: context,
            builder: (_) => const ApplicationInfoDialog(),
          );
      }
    } finally {
      if (mounted) setState(() => _settingsOpen = false);
    }
  }

  @override
  void initState() {
    super.initState();
    setDebugConsoleTheme(widget.debugConsole, preferences.themeMode);
    widget.controller.addListener(_synchronizeDebugConsole);
    _synchronizeDebugConsole();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker.cancel();
    widget.controller.removeListener(_synchronizeDebugConsole);
    unawaited(widget.debugConsole?.close() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> update(OverlayPreferences next) async {
    if (applyingPreferences) return;
    setState(() => applyingPreferences = true);
    var applied = false;
    try {
      await widget.window.setHud(next.hud);
      await widget.window.setAlwaysOnTop(next.alwaysOnTop);
      await widget.window.setOpacity(next.opacity);
      await widget.window.setCompact(next.compact);
      await widget.applyTheme?.call(next.themeMode);
      applied = true;
      if (mounted) {
        setState(() => preferences = next);
        widget.onThemeChanged?.call(next.themeMode);
        setDebugConsoleTheme(widget.debugConsole, next.themeMode);
      }
      await (widget.savePreferences?.call(next) ?? next.save());
    } on Object {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              applied
                  ? 'Window settings applied, but could not be saved.'
                  : 'Could not apply window settings.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => applyingPreferences = false);
    }
  }

  @override
  Widget build(BuildContext context) => preferences.hud
      ? CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                unawaited(update(preferences.copyWith(hud: false))),
          },
          child: Focus(
            autofocus: true,
            child: FluentScaffold(
              body: HudOverlay(
                controller: widget.controller,
                resetLabel: resetLabel,
                onDrag: widget.window.startDragging,
                onClose: widget.window.close,
                onExit: applyingPreferences
                    ? null
                    : () => unawaited(update(preferences.copyWith(hud: false))),
              ),
            ),
          ),
        )
      : Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.comma, control: true):
                _SettingsIntent(),
            SingleActivator(LogicalKeyboardKey.comma, meta: true):
                _SettingsIntent(),
            SingleActivator(LogicalKeyboardKey.keyR, control: true):
                _RefreshIntent(),
            SingleActivator(LogicalKeyboardKey.keyR, meta: true):
                _RefreshIntent(),
          },
          child: Actions(
            actions: {
              _SettingsIntent: CallbackAction<_SettingsIntent>(
                onInvoke: (_) {
                  unawaited(_openSettings());
                  return null;
                },
              ),
              _RefreshIntent: CallbackAction<_RefreshIntent>(
                onInvoke: (_) {
                  unawaited(widget.controller.refresh());
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: FluentScaffold(
                body: SafeArea(
                  child: AnimatedBuilder(
                    animation: widget.controller,
                    builder: (context, _) => Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: (_) =>
                                      unawaited(widget.window.startDragging()),
                                  child: FluentText(
                                    'LLM Quota',
                                    maxLines: 1,
                                    textOverflow: TextOverflow.ellipsis,
                                    style: FluentThemeDataModel.of(
                                      context,
                                    ).fluentTextTheme?.title2,
                                  ),
                                ),
                              ),
                              FluentActionButton(
                                tooltip: preferences.alwaysOnTop
                                    ? 'Unpin overlay'
                                    : 'Keep on top',
                                icon: Icon(
                                  preferences.alwaysOnTop
                                      ? FluentIcons.pin_20_filled
                                      : FluentIcons.pin_20_regular,
                                  size: 20,
                                ),
                                onPressed: applyingPreferences
                                    ? null
                                    : () => update(
                                        preferences.copyWith(
                                          alwaysOnTop: !preferences.alwaysOnTop,
                                        ),
                                      ),
                              ),
                              FluentActionButton(
                                tooltip: 'Overlay settings',
                                icon: const Icon(
                                  FluentIcons.settings_20_regular,
                                  size: 20,
                                ),
                                onPressed: applyingPreferences || _settingsOpen
                                    ? null
                                    : () => unawaited(_openSettings()),
                              ),
                              if (Theme.of(context).platform !=
                                  TargetPlatform.macOS)
                                FluentActionButton(
                                  tooltip: 'Close',
                                  icon: const Icon(
                                    FluentIcons.dismiss_20_regular,
                                    size: 20,
                                  ),
                                  onPressed: widget.window.close,
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.controller.debugMode
                                  ? (widget.controller.demo
                                        ? 'Debug · demo data'
                                        : 'Debug mode')
                                  : widget.controller.demo
                                  ? 'Demo · sample data'
                                  : 'Connected accounts',
                              style: TextStyle(
                                fontSize: Theme.of(
                                  context,
                                ).textTheme.bodySmall!.fontSize,
                                color: widget.controller.demo
                                    ? warningColor(context)
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _ResponsiveQuotaContent(
                            controller: widget.controller,
                            compact: preferences.compact,
                            onConnectDesktop: _connectClaudeDesktop,
                            configurationError:
                                widget.accountConfigurationError,
                            onManageAccounts: () => showDialog<void>(
                              context: context,
                              builder: (_) => AccountManagerDialog(
                                controller: widget.controller,
                                configurationError:
                                    widget.accountConfigurationError,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                          child: Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: widget.controller.demo
                                      ? warningColor(context)
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.controller.refreshing
                                      ? 'Refreshing…'
                                      : 'Auto-refresh · 60s',
                                  style: TextStyle(
                                    fontSize: Theme.of(
                                      context,
                                    ).textTheme.bodySmall!.fontSize,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              FluentActionButton(
                                tooltip: 'Refresh now (Ctrl/Cmd+R)',
                                onPressed: widget.controller.refreshing
                                    ? null
                                    : widget.controller.refresh,
                                icon: const Icon(
                                  FluentIcons.arrow_sync_20_regular,
                                  size: 17,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
}

class _ResponsiveQuotaContent extends StatelessWidget {
  const _ResponsiveQuotaContent({
    required this.controller,
    required this.compact,
    required this.onManageAccounts,
    this.onConnectDesktop,
    this.configurationError,
  });

  final QuotaController controller;
  final bool compact;
  final String? configurationError;
  final Future<String> Function()? onConnectDesktop;
  final VoidCallback onManageAccounts;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final snapshots = controller.visibleSnapshots;
      final padding = ((constraints.maxWidth * 0.025 / 4).round() * 4.0).clamp(
        12.0,
        24.0,
      );
      final contentWidth = (constraints.maxWidth - padding * 2).clamp(
        0.0,
        1440.0,
      );
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final minimumCardWidth = 320 * textScale.clamp(1.0, 1.5);
      final columns = ((contentWidth + 12) / (minimumCardWidth + 12))
          .floor()
          .clamp(1, 4);
      final cardWidth = (contentWidth - 12 * (columns - 1)) / columns;
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: padding, vertical: 4),
        child: Center(
          child: SizedBox(
            width: contentWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (configurationError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      configurationError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (snapshots.isEmpty)
                  _EmptyConnections(
                    refreshing: controller.refreshing,
                    onManageAccounts: onManageAccounts,
                    onConnectDesktop: onConnectDesktop,
                  )
                else
                  Wrap(
                    spacing: 12,
                    children: [
                      for (final snapshot in snapshots)
                        SizedBox(
                          width: cardWidth,
                          child: _ProviderCard(
                            provider: snapshot.provider,
                            snapshot: snapshot,
                            compact: compact,
                            now: DateTime.now(),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SettingsIntent extends Intent {
  const _SettingsIntent();
}

class _RefreshIntent extends Intent {
  const _RefreshIntent();
}

class _EmptyConnections extends StatelessWidget {
  const _EmptyConnections({
    required this.refreshing,
    required this.onManageAccounts,
    this.onConnectDesktop,
  });
  final Future<String> Function()? onConnectDesktop;
  final VoidCallback onManageAccounts;
  final bool refreshing;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            refreshing
                ? FluentIcons.arrow_sync_20_regular
                : FluentIcons.link_dismiss_20_regular,
            size: 28,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            refreshing ? 'Checking connections…' : 'No connected platforms',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!refreshing) ...[
            const SizedBox(height: 8),
            Text(
              'Connected accounts appear here automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FluentButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    _ConnectionHelp(onConnectDesktop: onConnectDesktop),
              ),
              title: 'Connect providers',
              variant: FluentButtonVariant.subtle,
            ),
            FluentButton(
              onPressed: onManageAccounts,
              title: 'Manage accounts',
              variant: FluentButtonVariant.subtle,
            ),
          ],
        ],
      ),
    ),
  );
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.snapshot,
    required this.compact,
    required this.now,
  });
  final ProviderKind provider;
  final QuotaSnapshot? snapshot;
  final bool compact;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final color = providerAccent(context, provider.index);
    final title = ['Codex', 'Claude', 'Antigravity'][provider.index];
    final status = snapshot?.status;
    final age = snapshot == null
        ? Duration.zero
        : now.toUtc().difference(snapshot!.observedAt);
    final stale =
        status == QuotaStatus.stale ||
        (status == QuotaStatus.live && age.inMinutes >= 10);
    final badge = stale
        ? 'Stale'
        : switch (status) {
            QuotaStatus.live => 'Connected',
            QuotaStatus.demo => 'Demo',
            QuotaStatus.error => 'Error',
            QuotaStatus.unavailable => 'Not connected',
            _ => 'Loading',
          };
    final card = FluentCardContainer(
      color: Theme.of(context).colorScheme.surfaceContainer,
      cornerRadius: FluentCornerRadius.large,
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (snapshot?.planName != null)
                      Tooltip(
                        message: snapshot!.planName!,
                        child: Text(
                          snapshot!.planName!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: Theme.of(
                              context,
                            ).textTheme.bodySmall!.fontSize,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  badge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Theme.of(context).textTheme.bodySmall!.fontSize,
                    color: stale || status == QuotaStatus.error
                        ? warningColor(context)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (snapshot?.accountLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Tooltip(
                message: snapshot!.accountLabel!,
                child: Text(
                  snapshot!.accountLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Theme.of(context).textTheme.bodyMedium!.fontSize,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          if (snapshot == null)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (snapshot != null && !snapshot!.hasUsage)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                snapshot!.message ?? 'No quota data available.',
                style: TextStyle(
                  fontSize: Theme.of(context).textTheme.bodyMedium!.fontSize,
                  height: Theme.of(context).textTheme.bodyMedium!.height,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final window in snapshot?.windows ?? <QuotaWindow>[])
            Padding(
              padding: EdgeInsets.only(top: compact ? 8 : 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          window.label,
                          style: TextStyle(
                            fontSize: Theme.of(
                              context,
                            ).textTheme.bodyMedium!.fontSize,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          window.remainingPercent == null
                              ? 'Unknown'
                              : '${window.remainingPercent!.toStringAsFixed(0)}% left',
                          style: TextStyle(
                            fontSize: Theme.of(
                              context,
                            ).textTheme.bodyMedium!.fontSize,
                            fontWeight: FontWeight.w600,
                            color:
                                window.remainingPercent != null &&
                                    window.remainingPercent! < 15
                                ? warningColor(context)
                                : color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (window.remainingPercent != null)
                    Semantics(
                      label:
                          '${window.label}: ${window.remainingPercent!.round()} percent remaining',
                      child: LinearProgressIndicator(
                        value: window.remainingPercent! / 100,
                        color: color,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                        minHeight: 4,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Tooltip(
                    message: window.resetsAt == null
                        ? 'The provider did not report a reset time.'
                        : 'Reset: ${window.resetsAt!.toLocal()}',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        resetLabel(window.resetsAt, now),
                        style: TextStyle(
                          fontSize: Theme.of(
                            context,
                          ).textTheme.bodySmall!.fontSize,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (snapshot != null) UsageSummary(snapshot: snapshot!),
          if (!compact && snapshot != null && snapshot!.hasUsage)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${snapshot!.source} · ${age.isNegative || age.inSeconds < 60 ? 'just now' : '${age.inMinutes}m ago'}${stale ? ' · refresh needed' : ''}',
                style: TextStyle(
                  fontSize: Theme.of(context).textTheme.bodySmall!.fontSize,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (snapshot?.message != null && snapshot!.hasUsage)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                snapshot!.message!,
                style: TextStyle(
                  fontSize: Theme.of(context).textTheme.bodySmall!.fontSize,
                  color: warningColor(context),
                ),
              ),
            ),
        ],
      ),
    );
    return FluentContainer(
      margin: const EdgeInsets.only(bottom: 12),
      cornerRadius: FluentCornerRadius.large,
      strokeStyle: FluentStrokeStyle(
        color: Theme.of(context).colorScheme.outlineVariant,
        thickness: FluentStrokeThickness.strokeWidth10,
      ),
      child: card,
    );
  }
}

String resetLabel(DateTime? resetsAt, DateTime now) {
  if (resetsAt == null) return 'Reset time unavailable';
  final duration = resetsAt.difference(now);
  if (duration <= Duration.zero) return 'Reset due · awaiting fresh data';
  if (duration.inDays > 0)
    return 'Resets in ${duration.inDays}d ${duration.inHours % 24}h';
  if (duration.inHours > 0)
    return 'Resets in ${duration.inHours}h ${duration.inMinutes % 60}m';
  return 'Resets in ${duration.inMinutes}m ${duration.inSeconds % 60}s';
}

class _ConnectionHelp extends StatefulWidget {
  const _ConnectionHelp({this.onConnectDesktop});
  final Future<String> Function()? onConnectDesktop;

  @override
  State<_ConnectionHelp> createState() => _ConnectionHelpState();
}

class _ConnectionHelpState extends State<_ConnectionHelp> {
  bool _connecting = false;
  String? _connectionStatus;

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _connectionStatus = null;
    });
    try {
      final String status;
      if (widget.onConnectDesktop != null) {
        status = await widget.onConnectDesktop!();
      } else {
        final connected = await QuotaSources.desktopService.requestAccess();
        status = connected
            ? 'Desktop access granted. Close this dialog and refresh quotas to load usage.'
            : 'Sign in to Claude Desktop before connecting.';
      }
      if (mounted) setState(() => _connectionStatus = status);
    } on Object catch (error) {
      if (mounted)
        setState(
          () => _connectionStatus = error is ClaudeDesktopException
              ? error.message
              : 'Could not connect to Claude Desktop. Sign in and allow Keychain access.',
        );
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ResponsiveSettingsSurface(
    title: const Text('Connect providers'),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SelectableText(
          'Codex\nInstall Codex CLI and sign in with your ChatGPT account. Quota reads limits through its app server.\n\n'
          'Claude Desktop (macOS)\nSign in to Claude Desktop, then select Connect Claude Desktop below. Allow access to Claude Safe Storage if macOS requests it. Usage is refreshed at most every five minutes.\n\n'
          'Claude Code\nThe included statusline bridge remains available for other platforms and separate account profiles. See README for the command.\n\n'
          'Antigravity\nStart the Antigravity desktop app. Quota detects its local language server. See README for manual endpoint overrides.\n\n'
          'Sample data is available under Settings > Debug settings. It is kept separate from account data.',
        ),
        if (_connectionStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_connectionStatus!),
          ),
      ],
    ),
    actions: [
      if (Theme.of(context).platform == TargetPlatform.macOS)
        FluentButton(
          onPressed: _connecting ? null : _connect,
          title: _connecting ? 'Connecting...' : 'Connect Claude Desktop',
          variant: FluentButtonVariant.accent,
        ),
      FluentButton(
        onPressed: () => Navigator.pop(context),
        title: 'Done',
        variant: FluentButtonVariant.subtle,
      ),
    ],
  );
}
