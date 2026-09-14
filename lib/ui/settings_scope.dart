import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_sessions.dart';
import '../state/device_store.dart';

enum SettingsScopeKind { workspace }

/// A real workspace tab for settings pages. The monitor/bridge is part of the
/// option identity; selecting another option must never reuse the old bridge.
class SettingsScopeOption {
  const SettingsScopeOption({
    required this.deviceId,
    required this.deviceLabel,
    required this.workspaceKey,
    required this.workspaceName,
    required this.workspacePath,
    required this.scope,
    required this.device,
    this.monitor,
  });

  final String deviceId;
  final String deviceLabel;
  final String workspaceKey;
  final String workspaceName;
  final String? workspacePath;
  final Map<String, dynamic> scope;
  final Device device;
  final WorkspaceMonitor? monitor;

  String get identity => '$deviceId|$workspaceKey';
  String get label => '$deviceLabel · $workspaceName';
  SettingsScopeKind get kind => SettingsScopeKind.workspace;
  bool get isOpen => monitor != null;

  @override
  bool operator ==(Object other) =>
      other is SettingsScopeOption && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;
}

/// Builds options from the session's actual workspace list and currently
/// opened monitors. A monitor is optional until the caller opens that tab.
List<SettingsScopeOption> buildSettingsScopeOptions(
  AppSessions sessions, {
  WorkspaceMonitor? current,
}) {
  final result = <String, SettingsScopeOption>{};
  for (final device in sessions.store.devices) {
    final session = sessions.sessionOf(device.id);
    for (final workspace
        in session?.workspaces ?? const <Map<String, dynamic>>[]) {
      final key = _string(workspace['workspaceIdentity']).isNotEmpty
          ? _string(workspace['workspaceIdentity'])
          : _string(workspace['workspacePath']);
      if (key.isEmpty) continue;
      final monitor = sessions.monitorFor(device.id, key);
      result['${device.id}|$key'] = SettingsScopeOption(
        deviceId: device.id,
        deviceLabel: device.label,
        workspaceKey: key,
        workspaceName: _string(workspace['name']).isEmpty
            ? key
            : _string(workspace['name']),
        workspacePath: _string(workspace['workspacePath']).isEmpty
            ? null
            : _string(workspace['workspacePath']),
        scope: {
          ...workspace,
          'workspaceIdentity': key,
          if (_string(workspace['workspacePath']).isNotEmpty)
            'workspacePath': _string(workspace['workspacePath']),
        },
        device: device,
        monitor: monitor,
      );
    }
  }
  if (current != null) {
    final key = '${current.source.deviceId}|${current.source.workspaceKey}';
    result.putIfAbsent(
      key,
      () => SettingsScopeOption(
        deviceId: current.source.deviceId,
        deviceLabel: current.source.deviceLabel,
        workspaceKey: current.source.workspaceKey,
        workspaceName: current.source.workspaceKey,
        workspacePath: current.source.workspacePath,
        scope: {
          ...current.scope,
          'workspaceIdentity': current.source.workspaceKey,
          if (current.source.workspacePath != null)
            'workspacePath': current.source.workspacePath,
        },
        device: _deviceForCurrent(sessions, current),
        monitor: current,
      ),
    );
  }
  return result.values.toList(growable: false);
}

Device _deviceForCurrent(AppSessions sessions, WorkspaceMonitor monitor) =>
    sessions.store.devices.firstWhere(
      (device) => device.id == monitor.source.deviceId,
      orElse: () => const Device(
        id: '',
        label: '',
        url: '',
        addedAt: 0,
        lastUsedAt: 0,
      ),
    );

String _string(Object? value) => value is String ? value.trim() : '';

class SettingsScopePicker extends StatelessWidget {
  const SettingsScopePicker({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<SettingsScopeOption> options;
  final SettingsScopeOption? selected;
  final FutureOr<void> Function(SettingsScopeOption option) onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final selectedOption =
        options.contains(selected) ? selected : options.first;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth.clamp(120.0, 280.0)
          : 280.0;
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: DropdownButton<SettingsScopeOption>(
          key: const ValueKey('settings-workspace-scope'),
          value: selectedOption,
          isDense: true,
          isExpanded: true,
          onChanged: (value) {
            if (value != null) {
              final result = onSelected(value);
              if (result is Future<void>) unawaited(result);
            }
          },
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: option,
                child: Text(option.label, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      );
    });
  }
}
