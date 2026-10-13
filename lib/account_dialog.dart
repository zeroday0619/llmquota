import 'package:flutter/material.dart';
import 'package:gbt_fluent2_ui/gbt_fluent2_ui.dart';
import 'package:gbt_fluent2_ui/fluent_icons.dart';

import 'settings_dialog.dart';

import 'models/quota.dart';
import 'models/quota_account.dart';
import 'services/quota_controller.dart';

String _providerName(ProviderKind provider) =>
    ['Codex', 'Claude', 'Antigravity'][provider.index];

class AccountManagerDialog extends StatefulWidget {
  const AccountManagerDialog({
    super.key,
    required this.controller,
    this.configurationError,
  });
  final QuotaController controller;
  final String? configurationError;

  @override
  State<AccountManagerDialog> createState() => _AccountManagerDialogState();
}

class _AccountManagerDialogState extends State<AccountManagerDialog> {
  bool saving = false;
  String? error;

  Future<void> save(List<QuotaAccount> accounts) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.setAccounts(accounts);
    } on Object {
      if (mounted)
        setState(
          () => error =
              'Could not save accounts. Your previous settings are unchanged.',
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> edit([QuotaAccount? account]) async {
    final result = await showDialog<QuotaAccount>(
      context: context,
      builder: (_) => _AccountEditor(account: account),
    );
    if (result == null || !mounted) return;
    await save([
      for (final current in widget.controller.accounts)
        if (current.id == result.id) result else current,
      if (account == null) result,
    ]);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => ResponsiveSettingsSurface(
      title: const Text('Manage accounts'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.configurationError != null)
              Text(
                widget.configurationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const Text(
              'Each profile reads an existing local sign-in. Removing a profile does not sign out or delete credentials.',
            ),
            if (widget.controller.demo)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Demo mode is active. Sample data does not show account connection status.',
                ),
              ),
            for (final account in widget.controller.accounts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: FluentSettingsGroup(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          account.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${_providerName(account.provider)} · ${status(account)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        Wrap(
                          alignment: WrapAlignment.end,
                          children: [
                            IconButton(
                              tooltip: 'Edit ${account.label}',
                              onPressed: saving ? null : () => edit(account),
                              icon: const Icon(FluentIcons.edit_20_regular),
                            ),
                            IconButton(
                              tooltip: 'Remove ${account.label}',
                              onPressed: saving
                                  ? null
                                  : () => save(
                                      widget.controller.accounts
                                          .where(
                                            (current) =>
                                                current.id != account.id,
                                          )
                                          .toList(),
                                    ),
                              icon: const Icon(FluentIcons.delete_20_regular),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (widget.controller.accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No accounts registered.'),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        if (QuotaAccount.defaults.any(
          (account) => !widget.controller.accounts.any(
            (current) => current.id == account.id,
          ),
        ))
          FluentButton(
            variant: FluentButtonVariant.subtle,
            onPressed: saving
                ? null
                : () => save([
                    ...widget.controller.accounts,
                    for (final account in QuotaAccount.defaults)
                      if (!widget.controller.accounts.any(
                        (current) => current.id == account.id,
                      ))
                        account,
                  ]),
            title: 'Restore default connections',
          ),
        FluentButton(
          onPressed: saving ? null : () => edit(),
          title: 'Add account',
        ),
        FluentButton(
          variant: FluentButtonVariant.subtle,
          onPressed: saving ? null : () => Navigator.pop(context),
          title: 'Done',
        ),
      ],
    ),
  );

  String status(QuotaAccount account) {
    if (widget.controller.demo) return 'Not checked in demo mode';
    final snapshot = widget.controller.snapshots[account.id];
    return switch (snapshot?.status) {
      QuotaStatus.live => 'Connected',
      QuotaStatus.stale => 'Stale data',
      QuotaStatus.error => 'Connection error',
      QuotaStatus.unavailable => 'Not connected',
      QuotaStatus.demo => 'Sample data',
      null => 'Not checked',
    };
  }
}

class _AccountEditor extends StatefulWidget {
  const _AccountEditor({this.account});
  final QuotaAccount? account;
  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  final form = GlobalKey<FormState>();
  String? validationError;
  late ProviderKind provider = widget.account?.provider ?? ProviderKind.codex;
  late final label = TextEditingController(text: widget.account?.label);
  late final directory = TextEditingController(
    text: widget.account?.configurationDirectory,
  );
  late final snapshot = TextEditingController(
    text: widget.account?.snapshotPath,
  );
  late final endpoint = TextEditingController(text: widget.account?.endpoint);
  late final csrf = TextEditingController(
    text: widget.account?.csrfTokenEnvironmentVariable,
  );
  bool get defaultConnection =>
      widget.account != null &&
      widget.account!.configurationDirectory == null &&
      widget.account!.snapshotPath == null &&
      widget.account!.endpoint == null;

  @override
  void dispose() {
    for (final controller in [label, directory, snapshot, endpoint, csrf]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? optional(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();

  void submit() {
    if (!form.currentState!.validate()) return;
    final account = QuotaAccount(
      id:
          widget.account?.id ??
          'account-${DateTime.now().microsecondsSinceEpoch}',
      provider: provider,
      label: label.text.trim(),
      configurationDirectory:
          defaultConnection || provider == ProviderKind.antigravity
          ? null
          : optional(directory),
      snapshotPath: !defaultConnection && provider == ProviderKind.claude
          ? optional(snapshot)
          : null,
      endpoint: !defaultConnection && provider == ProviderKind.antigravity
          ? optional(endpoint)
          : null,
      csrfTokenEnvironmentVariable:
          !defaultConnection && provider == ProviderKind.antigravity
          ? optional(csrf)
          : null,
    );
    try {
      account.validate();
    } on FormatException catch (error) {
      setState(() => validationError = error.message);
      return;
    } on ArgumentError catch (error) {
      setState(() => validationError = error.message.toString());
      return;
    }
    Navigator.pop(context, account);
  }

  @override
  Widget build(BuildContext context) => ResponsiveSettingsSurface(
    title: Text(widget.account == null ? 'Add account' : 'Edit account'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (validationError != null)
              Text(
                validationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            DropdownButtonFormField<ProviderKind>(
              isExpanded: true,
              initialValue: provider,
              decoration: const InputDecoration(labelText: 'Provider'),
              items: [
                for (final kind in ProviderKind.values)
                  DropdownMenuItem(
                    value: kind,
                    child: Text(_providerName(kind)),
                  ),
              ],
              onChanged: widget.account != null
                  ? null
                  : (value) => setState(() => provider = value!),
            ),
            _FluentAccountField(
              key: ValueKey(label),
              controller: label,
              decoration: const InputDecoration(labelText: 'Account label'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter an account label.'
                  : null,
            ),
            if (defaultConnection)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'This profile uses the existing local connection and environment settings. Add another account to configure a separate connection.',
                ),
              ),
            if (!defaultConnection && provider != ProviderKind.antigravity)
              _FluentAccountField(
                key: ValueKey(directory),
                controller: directory,
                decoration: InputDecoration(
                  labelText: provider == ProviderKind.codex
                      ? 'Codex home directory'
                      : 'Claude configuration directory',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter this account’s configuration directory.'
                    : null,
              ),
            if (!defaultConnection && provider == ProviderKind.claude)
              _FluentAccountField(
                key: ValueKey(snapshot),
                controller: snapshot,
                decoration: const InputDecoration(
                  labelText: 'Claude snapshot file',
                  helperText:
                      'Use the output path of this account’s statusline bridge.',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter this account’s snapshot file.'
                    : null,
              ),
            if (!defaultConnection && provider == ProviderKind.antigravity) ...[
              _FluentAccountField(
                key: ValueKey(endpoint),
                controller: endpoint,
                decoration: const InputDecoration(
                  labelText: 'Antigravity loopback URL',
                  hintText: 'http://127.0.0.1:42100',
                ),
                validator: (value) {
                  final uri = Uri.tryParse(value?.trim() ?? '');
                  if (uri == null ||
                      !['http', 'https'].contains(uri.scheme) ||
                      !['127.0.0.1', '::1', '[::1]'].contains(uri.host) ||
                      uri.userInfo.isNotEmpty ||
                      uri.hasQuery ||
                      uri.hasFragment)
                    return 'Enter a local HTTP(S) URL without credentials.';
                  return null;
                },
              ),
              _FluentAccountField(
                key: ValueKey(csrf),
                controller: csrf,
                decoration: const InputDecoration(
                  labelText: 'CSRF environment variable (optional)',
                  helperText: 'Variable name only. Do not enter a token.',
                ),
                validator: (value) =>
                    value != null &&
                        value.trim().isNotEmpty &&
                        !RegExp(
                          r'^[A-Za-z_][A-Za-z0-9_]*$',
                        ).hasMatch(value.trim())
                    ? 'Enter an environment variable name.'
                    : null,
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      FluentButton(
        variant: FluentButtonVariant.subtle,
        onPressed: () => Navigator.pop(context),
        title: 'Cancel',
      ),
      FluentButton(onPressed: submit, title: 'Save'),
    ],
  );
}

/// Retains form validation while presenting the provider connection fields in Fluent.
class _FluentAccountField extends StatefulWidget {
  const _FluentAccountField({
    super.key,
    required this.controller,
    required this.decoration,
    required this.validator,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final FormFieldValidator<String> validator;

  @override
  State<_FluentAccountField> createState() => _FluentAccountFieldState();
}

class _FluentAccountFieldState extends State<_FluentAccountField> {
  late final FluentTextFieldController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FluentTextFieldController();
    _controller.textEditingController.text = widget.controller.text;
    _controller.textEditingController.addListener(_updateValue);
  }

  void _updateValue() {
    widget.controller.value = _controller.textEditingController.value;
  }

  @override
  void dispose() {
    _controller.textEditingController.removeListener(_updateValue);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormField<String>(
    initialValue: widget.controller.text,
    validator: (_) => widget.validator(widget.controller.text),
    builder: (field) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FluentTextField(
        controller: _controller,
        label: widget.decoration.labelText,
        hintText: widget.decoration.hintText,
        assistiveText: widget.decoration.helperText,
        hasError: field.hasError,
        errorText: field.errorText,
        onChanged: field.didChange,
      ),
    ),
  );
}
