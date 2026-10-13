import 'package:flutter/material.dart';
import 'package:gbt_fluent2_ui/gbt_fluent2_ui.dart';
import 'package:gbt_fluent2_ui/fluent_icons.dart';

import 'services/preferences.dart';
import 'services/quota_controller.dart';

enum SettingsSection { display, accounts, connections, diagnostics, about }

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) => ResponsiveSettingsSurface(
    title: const Text('Settings'),
    content: FluentSettingsGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _section(
            context,
            SettingsSection.display,
            FluentIcons.desktop_20_regular,
            'Display settings',
            'Theme, HUD, compact view, opacity, and pinning.',
          ),
          _section(
            context,
            SettingsSection.accounts,
            FluentIcons.people_20_regular,
            'Manage accounts',
            'Add, edit, or remove account profiles.',
          ),
          _section(
            context,
            SettingsSection.connections,
            FluentIcons.link_20_regular,
            'Connect providers',
            'Local provider setup and connection requirements.',
          ),
          _section(
            context,
            SettingsSection.diagnostics,
            FluentIcons.bug_20_regular,
            'Debug settings',
            'Communication logs and sample data.',
          ),
          _section(
            context,
            SettingsSection.about,
            FluentIcons.info_20_regular,
            'About llmquota',
            'Developer, version, and licenses.',
          ),
        ],
      ),
    ),
    actions: [
      FluentButton(
        variant: FluentButtonVariant.subtle,
        onPressed: () => Navigator.pop(context),
        title: 'Done',
      ),
    ],
  );

  Widget _section(
    BuildContext context,
    SettingsSection section,
    IconData icon,
    String title,
    String subtitle,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: Icon(
      icon,
      size: 20,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(FluentIcons.chevron_right_20_regular),
    onTap: () => Navigator.pop(context, section),
  );
}

class DisplaySettingsDialog extends StatefulWidget {
  const DisplaySettingsDialog({super.key, required this.preferences});

  final OverlayPreferences preferences;

  @override
  State<DisplaySettingsDialog> createState() => _DisplaySettingsDialogState();
}

class _DisplaySettingsDialogState extends State<DisplaySettingsDialog> {
  late OverlayPreferences _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.preferences;
  }

  @override
  Widget build(BuildContext context) => ResponsiveSettingsSurface(
    title: const Text('Display settings'),
    content: FluentSettingsGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<AppThemeMode>(
              isExpanded: true,
              key: ValueKey(_draft.themeMode),
              initialValue: _draft.themeMode,
              decoration: const InputDecoration(labelText: 'Theme'),
              items: const [
                DropdownMenuItem(value: AppThemeMode.dark, child: Text('Dark')),
                DropdownMenuItem(
                  value: AppThemeMode.light,
                  child: Text('Light'),
                ),
                DropdownMenuItem(
                  value: AppThemeMode.oledBlack,
                  child: Text('OLED black'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _draft = _draft.copyWith(themeMode: value));
                }
              },
            ),
          ),
          FluentSettingsSwitchTile(
            title: const Text('HUD mode'),
            value: _draft.hud,
            onChanged: (value) =>
                setState(() => _draft = _draft.copyWith(hud: value)),
          ),
          FluentSettingsSwitchTile(
            title: const Text('Compact view'),
            value: _draft.compact,
            onChanged: (value) =>
                setState(() => _draft = _draft.copyWith(compact: value)),
          ),
          FluentSettingsSwitchTile(
            title: const Text('Keep on top'),
            value: _draft.alwaysOnTop,
            onChanged: (value) =>
                setState(() => _draft = _draft.copyWith(alwaysOnTop: value)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Opacity: ${(_draft.opacity * 100).round()}%'),
          ),
          Slider(
            min: 0.45,
            max: 1,
            divisions: 55,
            value: _draft.opacity.clamp(0.45, 1),
            label: '${(_draft.opacity * 100).round()}%',
            onChanged: (value) =>
                setState(() => _draft = _draft.copyWith(opacity: value)),
          ),
          FluentButton(
            variant: FluentButtonVariant.subtle,
            onPressed: () =>
                setState(() => _draft = const OverlayPreferences()),
            title: 'Restore defaults',
          ),
        ],
      ),
    ),
    actions: [
      FluentButton(
        variant: FluentButtonVariant.subtle,
        onPressed: () => Navigator.pop(context),
        title: 'Cancel',
      ),
      FluentButton(
        onPressed: () => Navigator.pop(context, _draft),
        title: 'Apply',
      ),
    ],
  );
}

class DiagnosticsSettingsDialog extends StatelessWidget {
  const DiagnosticsSettingsDialog({
    super.key,
    required this.controller,
    required this.onOpenConsole,
  });

  final QuotaController controller;
  final VoidCallback onOpenConsole;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => ResponsiveSettingsSurface(
      title: const Text('Debug settings'),
      content: FluentSettingsGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('These settings apply only to the current session.'),
            ),
            FluentSettingsSwitchTile(
              title: const Text('Debug mode'),
              value: controller.debugMode,
              onChanged: controller.setDebugMode,
            ),
            FluentSettingsSwitchTile(
              title: const Text('Demo data'),
              value: controller.demo,
              onChanged: controller.setDemo,
            ),
            FluentButton(
              onPressed: controller.debugMode ? onOpenConsole : null,
              title: 'Open debug console',
            ),
            FluentButton(
              variant: FluentButtonVariant.subtle,
              onPressed: controller.debugMode && controller.debugLogs.isNotEmpty
                  ? controller.clearDebugLogs
                  : null,
              title: 'Clear logs',
            ),
          ],
        ),
      ),
      actions: [
        FluentButton(
          variant: FluentButtonVariant.subtle,
          onPressed: () => Navigator.pop(context),
          title: 'Done',
        ),
      ],
    ),
  );
}

/// Keeps every dialog control reachable when height or text size is constrained.
class ResponsiveSettingsSurface extends StatelessWidget {
  const ResponsiveSettingsSurface({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 584),
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                namesRoute: true,
                child: DefaultTextStyle(
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w600),
                  child: title,
                ),
              ),
              const SizedBox(height: 24),
              content,
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Groups related settings while retaining the selected theme's surface colors.
class FluentSettingsGroup extends StatelessWidget {
  const FluentSettingsGroup({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FluentCardContainer(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    cornerRadius: FluentCornerRadius.large,
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}

/// Makes the complete setting row operable with the Fluent switch control.
class FluentSettingsSwitchTile extends StatelessWidget {
  const FluentSettingsSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: FluentSwitchToggle(value: value, onChanged: onChanged),
    ),
  );
}
