import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:gbt_fluent2_ui/gbt_fluent2_ui.dart';
import 'package:gbt_fluent2_ui/fluent_icons.dart';

import 'settings_dialog.dart';
import 'package:flutter/services.dart';

class ApplicationInfoDialog extends StatefulWidget {
  const ApplicationInfoDialog({
    super.key,
    this.assetBundle,
    this.buildName = const String.fromEnvironment('FLUTTER_BUILD_NAME'),
    this.buildNumber = const String.fromEnvironment('FLUTTER_BUILD_NUMBER'),
  });

  final AssetBundle? assetBundle;
  final String buildName;
  final String buildNumber;

  @override
  State<ApplicationInfoDialog> createState() => _ApplicationInfoDialogState();
}

class _ApplicationInfoDialogState extends State<ApplicationInfoDialog> {
  late final Future<String?> _version = _loadVersion();

  AssetBundle get _assets => widget.assetBundle ?? rootBundle;

  Future<String?> _loadVersion() async {
    final buildName = widget.buildName;
    final buildNumber = widget.buildNumber;
    if (buildName.isNotEmpty) {
      return buildNumber.isEmpty ? buildName : '$buildName+$buildNumber';
    }
    try {
      final manifest = await _assets.loadString('pubspec.yaml');
      return RegExp(
        r'^version:\s*([^\r\n]+)',
        multiLine: true,
      ).firstMatch(manifest)?.group(1)?.trim();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => ResponsiveSettingsSurface(
    title: const Text('App information'),
    content: SizedBox(
      width: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Column(
              children: [
                Icon(
                  FluentIcons.data_usage_20_regular,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text('llmquota', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('Developer: zeroday0619'),
          const SizedBox(height: 8),
          FutureBuilder<String?>(
            future: _version,
            builder: (context, snapshot) => Text(
              'Version: ${snapshot.connectionState == ConnectionState.done ? snapshot.data ?? 'Unavailable' : 'Loading'}',
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Application license'),
            subtitle: const Text('The Unlicense'),
            trailing: const Icon(FluentIcons.chevron_right_20_regular),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => _ApplicationLicenseDialog(assets: _assets),
            ),
          ),
          FutureBuilder<String?>(
            future: _version,
            builder: (context, snapshot) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Open-source notices'),
              subtitle: const Text('Dependency licenses and notices'),
              trailing: const Icon(FluentIcons.chevron_right_20_regular),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const _OpenSourceNoticesDialog(),
              ),
            ),
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
}

class _ApplicationLicenseDialog extends StatefulWidget {
  const _ApplicationLicenseDialog({required this.assets});

  final AssetBundle assets;

  @override
  State<_ApplicationLicenseDialog> createState() =>
      _ApplicationLicenseDialogState();
}

class _ApplicationLicenseDialogState extends State<_ApplicationLicenseDialog> {
  late final Future<String> _license = widget.assets.loadString('LICENSE');

  @override
  Widget build(BuildContext context) => ResponsiveSettingsSurface(
    title: const Text('The Unlicense'),
    content: SizedBox(
      width: 520,
      child: FutureBuilder<String>(
        future: _license,
        builder: (context, snapshot) => SelectableText(
          snapshot.hasError
              ? 'Application license could not be loaded.'
              : snapshot.data ?? 'Loading license...',
        ),
      ),
    ),
    actions: [
      FluentButton(
        variant: FluentButtonVariant.subtle,
        onPressed: () => Navigator.pop(context),
        title: 'Close',
      ),
    ],
  );
}

class _OpenSourceNoticesDialog extends StatefulWidget {
  const _OpenSourceNoticesDialog();

  @override
  State<_OpenSourceNoticesDialog> createState() =>
      _OpenSourceNoticesDialogState();
}

class _OpenSourceNoticesDialogState extends State<_OpenSourceNoticesDialog> {
  late final Future<Map<String, List<LicenseEntry>>> _notices = _loadNotices();

  Future<Map<String, List<LicenseEntry>>> _loadNotices() async {
    final notices = <String, List<LicenseEntry>>{};
    await for (final license in LicenseRegistry.licenses) {
      for (final package in license.packages) {
        notices.putIfAbsent(package, () => []).add(license);
      }
    }
    return Map.fromEntries(
      notices.entries.toList()
        ..sort((first, second) => first.key.compareTo(second.key)),
    );
  }

  @override
  Widget build(BuildContext context) => ResponsiveSettingsSurface(
    title: const Text('Open-source notices'),
    content: FutureBuilder<Map<String, List<LicenseEntry>>>(
      future: _notices,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Dependency notices could not be loaded.');
        }
        if (!snapshot.hasData) return const Text('Loading notices...');
        if (snapshot.data!.isEmpty) {
          return const Text('No dependency notices are registered.');
        }
        return FluentSettingsGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final notice in snapshot.data!.entries)
                ListTile(
                  title: Text(notice.key),
                  subtitle: Text('${notice.value.length} license notice(s)'),
                  trailing: const Icon(FluentIcons.chevron_right_20_regular),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => ResponsiveSettingsSurface(
                      title: Text(notice.key),
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final license in notice.value)
                            for (final paragraph in license.paragraphs)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: SelectableText(paragraph.text),
                              ),
                        ],
                      ),
                      actions: [
                        FluentButton(
                          variant: FluentButtonVariant.subtle,
                          onPressed: () => Navigator.pop(context),
                          title: 'Close',
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
    actions: [
      FluentButton(
        variant: FluentButtonVariant.subtle,
        onPressed: () => Navigator.pop(context),
        title: 'Close',
      ),
    ],
  );
}
