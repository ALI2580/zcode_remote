import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, MethodChannel, MissingPluginException;
import '../notifications/task_target.dart';
import '../protocol/channel_client.dart';
import '../protocol/entitlement.dart';
import '../state/app_sessions.dart';
import '../state/composer_store.dart';
import '../state/client_preferences.dart';
import '../state/device_store.dart';
import '../state/coding_plan_upgrade.dart';
import '../state/remote_profile.dart';
import '../state/remote_settings.dart';
import '../state/mcp_catalog.dart';
import '../state/settings_import.dart';
import '../state/remote_agent_catalogs.dart';
import '../state/model_provider_catalog.dart';
import '../state/model_connectivity.dart';
import '../state/model_captcha.dart';
import '../state/skills_catalog.dart';
import 'plugin_marketplace.dart';
import 'plugins_settings.dart';
import 'commands_settings.dart';
import 'command_form_dialog.dart';
import 'subagents_settings.dart';
import '../state/plugin_catalog.dart';
import '../update/app_version.dart';
import '../update/update_channel.dart';
import '../update/update_checker.dart';
import '../update/update_downloader.dart';
import 'upgrade_page.dart';
import 'usage/usage_page.dart';
import 'notification_settings_page.dart';
import 'appearance_settings_page.dart';
import 'official_icons.dart';
import 'theme.dart';
import 'voice_model_manager.dart';
import 'device_connection_status.dart';
import 'device_directory.dart';
import 'model_connectivity_button.dart';
import 'mcp_settings.dart';
import 'onboarding_wizard.dart';
import 'settings_import_dialog.dart';
import 'settings_scope.dart';
import 'model_provider_editor.dart';
import 'skills_settings.dart';
import 'settings_navigation_result.dart';
import 'hooks_settings.dart';

class SettingsCenterPage extends StatefulWidget {
  const SettingsCenterPage(
      {super.key,
      required this.preferences,
      required this.sessions,
      required this.onManageDevices,
      this.onOpenDevice,
      this.onOpenExternal,
      this.remoteMonitor,
      this.initialSection = 'general'});
  final ClientPreferences preferences;
  final AppSessions sessions;
  final VoidCallback onManageDevices;
  final Future<void> Function(Device)? onOpenDevice;

  /// Host supplied external-browser opener for MCP OAuth authorization URLs.
  final Future<void> Function(String url)? onOpenExternal;
  final WorkspaceMonitor? remoteMonitor;
  final String initialSection;
  @override
  State<SettingsCenterPage> createState() => _SettingsCenterPageState();
}

class _SettingsCenterPageState extends State<SettingsCenterPage> {
  late String _section;
  late bool _devicesVisited, _usageVisited;
  bool _checking = false;
  String? _updateError;
  UpdateInfo? _update;
  UpdateDownloader? _downloader;
  RemoteSettingsController? _remoteSettings;
  // Remote settings are owned by AppSessions so ChatPage instances keep the
  // same confirmed projection after this route is closed.
  bool _ownsRemoteSettings = false;
  SkillsCatalog? _skillsCatalog;
  WorkspaceMonitor? _skillsWorkspaceMonitor;
  SettingsScopeOption? _skillsWorkspaceScope;
  int _skillsWorkspaceSelectionGeneration = 0;
  String _skillsScope = 'user';
  PluginCatalog? _skillsPlugins;
  McpCatalog? _mcpCatalog;
  WorkspaceMonitor? _mcpWorkspaceMonitor;
  SettingsScopeOption? _mcpWorkspaceScope;
  int _mcpWorkspaceSelectionGeneration = 0;
  SubagentsCatalog? _subagentsCatalog;
  WorkspaceMonitor? _subagentsWorkspaceMonitor;
  int _subagentsWorkspaceSelectionGeneration = 0;
  ModelProvidersCatalog? _subagentsModelProviders;
  CommandsCatalog? _commandsCatalog;
  WorkspaceMonitor? _commandsWorkspaceMonitor;
  int _commandsWorkspaceSelectionGeneration = 0;
  final _commandsFormTargets = <String, CommandsCatalog>{};
  final _commandsFormTargetMonitors = <String, WorkspaceMonitor>{};
  ModelProvidersCatalog? _modelProviders;
  ModelConnectivityController? _modelConnectivity;
  // Official ModelProviderSection two-pane selection state: which provider
  // row the detail pane shows (official-settings-model-2026-09-12).
  String? _selectedProviderId;
  // Official preset nav row (智谱 group): selecting the family brand row shows
  // the family connection detail instead of a single provider row.
  String? _selectedModelFamily;
  // Read-only plan summary for the provider detail card (E2.1 pricing).
  CodingPlanUpgradeCatalog? _upgradeCatalog;
  // Official provider plan card: entitlement projection fields
  // (subscriptionRenewTime/ExpireTime + quotaLimits/mcpQuotaLimit in the
  // VGt component) come from the verified read-only
  // usageService.getEntitlementSnapshot, keyed to the selected provider.
  EntitlementSnapshot? _planEntitlement;
  bool _planEntitlementLoading = false;
  int _planEntitlementGeneration = 0;
  // Providers whose keyed entitlement read failed; the plan card stays
  // hidden for them instead of spinning forever.
  final Set<String> _planEntitlementFailed = {};
  // Official ModelProviderSection connection items: the API-key preset, the
  // coding-plan OAuth key and one entry per subscribed team project. Team
  // candidates come from `getEnterprisePricing`; failures only hide the team
  // entries, the other two stay selectable.
  final _familyOptions = <String, List<FamilyConnectionOption>>{};
  final _familyOptionsFailed = <String>{};
  int _familyOptionsGeneration = 0;
  RemoteProfile? _profile;
  // Official general page: the integrated-shell select renders only when the
  // desktop reports platform win32, and the shell options come from
  // `systemService.listIntegratedTerminalShells`. Both are read-only calls;
  // failures degrade exactly like the official page (select hidden or the
  // auto-only entry).
  String? _remotePlatform;
  List<Map<String, Object?>> _terminalShells = const [];
  int _systemInfoGeneration = 0;
  // Official browser page "开启内置浏览器控制" toggles the browser-use
  // official plugin through the same verified pluginManagement write as
  // the plugins section; it is not a settingService key.
  PluginCatalog? _browserPlugins;
  PluginCatalog? _pluginsCatalog;
  WorkspaceMonitor? _pluginsWorkspaceMonitor;
  SettingsScopeOption? _pluginsWorkspaceScope;
  String _pluginsScope = 'user';
  int _pluginsWorkspaceSelectionGeneration = 0;
  PluginCatalog? _mcpPlugins;
  PluginCatalog? _hooksPlugins;
  HooksCatalog? _hooksCatalog;
  WorkspaceMonitor? _hooksWorkspaceMonitor;
  String _hooksScopeKey = 'user';
  int _hooksWorkspaceSelectionGeneration = 0;
  // Local search filters for the subagents/commands pages (official pages
  // carry a search box next to the scope pill; filtering happens client
  // side over the verified list read).
  String _mcpScope = 'user';
  final _sectionScrollControllers = <String, ScrollController>{};
  final _sectionScrollOffsets = <String, double>{};
  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    _devicesVisited = _section == 'devices';
    _usageVisited = _section == 'usage';
    unawaited(widget.preferences.load());
    unawaited(updateChannelSettings.load().then((_) {
      if (mounted) setState(() {});
    }));
    _syncRemoteSettings();
  }

  void _startDownload(BuildContext context) {
    final assets = _update?.assets ?? [];
    if (assets.isEmpty) return;
    final asset = assets.first;
    _downloader ??= UpdateDownloader();
    _downloader!.download(url: asset.apkUrl);
  }

  @override
  void dispose() {
    for (final controller in _sectionScrollControllers.values) {
      controller.dispose();
    }
    if (_ownsRemoteSettings) _remoteSettings?.dispose();
    _modelConnectivity?.dispose();
    _subagentsCatalog?.dispose();
    _commandsCatalog?.dispose();
    _subagentsModelProviders?.dispose();
    for (final target in _commandsFormTargets.values) {
      if (!identical(target, _commandsCatalog)) target.dispose();
    }
    _commandsFormTargets.clear();
    _commandsFormTargetMonitors.clear();
    _skillsCatalog?.dispose();
    _mcpCatalog?.dispose();
    _downloader?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SettingsCenterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remoteMonitor != widget.remoteMonitor) {
      _subagentsWorkspaceSelectionGeneration++;
      _subagentsWorkspaceMonitor = widget.remoteMonitor;
      _commandsWorkspaceSelectionGeneration++;
      _commandsWorkspaceMonitor = widget.remoteMonitor;
      _mcpWorkspaceSelectionGeneration++;
      _mcpWorkspaceMonitor = widget.remoteMonitor;
      _mcpWorkspaceScope = null;
      _skillsWorkspaceSelectionGeneration++;
      _skillsWorkspaceMonitor = widget.remoteMonitor;
      _skillsWorkspaceScope = null;
      _skillsScope = 'user';
      _hooksWorkspaceSelectionGeneration++;
      _hooksWorkspaceMonitor = widget.remoteMonitor;
      _hooksScopeKey = 'user';
      _pluginsWorkspaceSelectionGeneration++;
      _pluginsWorkspaceMonitor = widget.remoteMonitor;
      _pluginsWorkspaceScope = null;
      _pluginsScope = 'user';
      _syncRemoteSettings();
    }
  }

  ScrollController _scrollControllerFor(String section) {
    return _sectionScrollControllers.putIfAbsent(section, () {
      final controller = ScrollController();
      controller.addListener(() {
        if (controller.hasClients) {
          _sectionScrollOffsets[section] = controller.offset;
        }
      });
      return controller;
    });
  }

  void _selectSection(String section) {
    if (_section == section &&
        (section != 'devices' || _devicesVisited) &&
        (section != 'usage' || _usageVisited)) {
      return;
    }
    setState(() {
      _section = section;
      if (section == 'devices') _devicesVisited = true;
      if (section == 'usage') _usageVisited = true;
    });
    // A section's scroll view is offstage while another section is active, so
    // Flutter may detach and dispose its position. Restore the last user
    // offset after the section is attached again; this also preserves the
    // embedded Usage tab/range state without nesting another route.
    _restoreSectionOffset(section);
  }

  void _restoreSectionOffset(String section, [int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _section != section) return;
      final controller = _scrollControllerFor(section);
      if (!controller.hasClients) {
        if (attempt < 3) _restoreSectionOffset(section, attempt + 1);
        return;
      }
      final position = controller.position;
      if (!position.hasContentDimensions) {
        if (attempt < 3) _restoreSectionOffset(section, attempt + 1);
        return;
      }
      final saved = _sectionScrollOffsets[section] ?? 0;
      final target = saved.clamp(0.0, position.maxScrollExtent);
      if ((controller.offset - target).abs() > 0.1) {
        controller.jumpTo(target);
      }
    });
  }

  bool _restoreSectionFromMetrics(ScrollMetricsNotification notification) {
    final section = _section;
    final saved = _sectionScrollOffsets[section] ?? 0;
    if (saved <= 0) return false;
    final controller = _sectionScrollControllers[section];
    if (controller == null || !controller.hasClients) return false;
    final target = saved.clamp(0.0, notification.metrics.maxScrollExtent);
    if ((controller.offset - target).abs() <= 0.1) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _section != section || !controller.hasClients) return;
      final currentTarget =
          saved.clamp(0.0, controller.position.maxScrollExtent);
      if ((controller.offset - currentTarget).abs() > 0.1) {
        controller.jumpTo(currentTarget);
      }
    });
    return false;
  }

  void _syncRemoteSettings() {
    final monitor = widget.remoteMonitor;
    if (monitor == null) {
      _mcpWorkspaceSelectionGeneration++;
      if (_ownsRemoteSettings) _remoteSettings?.dispose();
      _remoteSettings = null;
      _ownsRemoteSettings = false;
      _skillsCatalog?.dispose();
      _skillsCatalog = null;
      _skillsPlugins = null;
      _skillsWorkspaceMonitor = null;
      _skillsWorkspaceScope = null;
      _skillsScope = 'user';
      _mcpCatalog?.dispose();
      _mcpCatalog = null;
      _mcpPlugins = null;
      _mcpWorkspaceMonitor = null;
      _mcpWorkspaceScope = null;
      _pluginsWorkspaceSelectionGeneration++;
      _pluginsWorkspaceMonitor = null;
      _pluginsWorkspaceScope = null;
      _pluginsScope = 'user';
      // Plugin catalogs are AppSessions-owned shared instances. Clearing a
      // page borrow must not dispose the catalog used by another capability.
      _pluginsCatalog = null;
      _hooksWorkspaceSelectionGeneration++;
      _hooksWorkspaceMonitor = null;
      _hooksScopeKey = 'user';
      _hooksPlugins = null;
      _subagentsWorkspaceSelectionGeneration++;
      _subagentsWorkspaceMonitor = null;
      _commandsWorkspaceSelectionGeneration++;
      _commandsWorkspaceMonitor = null;
      _subagentsCatalog?.dispose();
      _subagentsCatalog = null;
      final listCatalog = _commandsCatalog;
      _commandsCatalog?.dispose();
      _commandsCatalog = null;
      for (final target in _commandsFormTargets.values) {
        if (!identical(target, listCatalog)) target.dispose();
      }
      _commandsFormTargets.clear();
      _commandsFormTargetMonitors.clear();
      _subagentsModelProviders?.dispose();
      _subagentsModelProviders = null;
      _modelProviders?.dispose();
      _upgradeCatalog?.dispose();
      _upgradeCatalog = null;
      _modelConnectivity?.dispose();
      _modelConnectivity = null;
      _commandsCatalog = null;
      _browserPlugins = null;
      _hooksCatalog?.dispose();
      _hooksCatalog = null;
      return;
    }
    final scopeKey =
        '${monitor.source.deviceId}|${monitor.source.workspaceKey}';
    if (_remoteSettings != null &&
        identical(_remoteSettings!.session, monitor.bridge) &&
        _remoteSettings!.scopeKey == scopeKey) {
      return;
    }
    if (_ownsRemoteSettings) _remoteSettings?.dispose();
    _remoteSettings = widget.sessions.remoteSettingsForMonitor(monitor);
    _ownsRemoteSettings = false;
    final settings = _remoteSettings!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_remoteSettings, settings)) return;
      unawaited(settings.refresh());
    });
    unawaited(_loadSystemInfo(monitor));
    final browserPlugins = widget.sessions.pluginCatalogForMonitor(
      monitor,
      selectedScope: 'user',
    );
    if (!identical(_browserPlugins, browserPlugins)) {
      _browserPlugins = browserPlugins;
      unawaited(browserPlugins.refresh());
    }
    final pluginsMonitor = _pluginsWorkspaceMonitor ?? monitor;
    final pluginsCatalog = widget.sessions.pluginCatalogForMonitor(
      pluginsMonitor,
      selectedScope: _pluginsScope,
    );
    if (!identical(_pluginsCatalog, pluginsCatalog)) {
      _pluginsCatalog = pluginsCatalog;
      unawaited(pluginsCatalog.refresh());
    }
    _skillsWorkspaceMonitor ??= monitor;
    final skillsMonitor = _skillsWorkspaceMonitor!;
    final skillsScopeKey =
        '${skillsMonitor.source.deviceId}|${skillsMonitor.source.workspaceKey}';
    final skillsWorkspacePath = skillsMonitor.source.workspacePath ??
        (skillsMonitor.scope['workspacePath'] is String
            ? skillsMonitor.scope['workspacePath'] as String
            : null);
    final skillsPlugins = widget.sessions.pluginCatalogForMonitor(
      skillsMonitor,
      selectedScope: _skillsScope,
    );
    if (!identical(_skillsPlugins, skillsPlugins)) {
      _skillsPlugins = skillsPlugins;
      unawaited(skillsPlugins.refresh());
    }
    final mcpMonitor = _mcpWorkspaceMonitor ?? monitor;
    final mcpScopeKey =
        '${mcpMonitor.source.deviceId}|${mcpMonitor.source.workspaceKey}';
    final mcpWorkspacePath = mcpMonitor.source.workspacePath ??
        (mcpMonitor.scope['workspacePath'] is String
            ? mcpMonitor.scope['workspacePath'] as String
            : null);
    if (!(_mcpCatalog != null &&
        identical(_mcpCatalog!.session, mcpMonitor.bridge) &&
        _mcpCatalog!.scopeKey == mcpScopeKey &&
        _mcpCatalog!.workspacePath == mcpWorkspacePath)) {
      _mcpCatalog?.dispose();
      _mcpCatalog = McpCatalog(
        session: mcpMonitor.bridge,
        scope: mcpMonitor.scope,
        scopeKey: mcpScopeKey,
        workspacePath: mcpWorkspacePath,
        onConfigurationChanged: () => _invalidateComposerPrep(
          scopeMonitor: mcpMonitor,
        ),
      );
      unawaited(_mcpCatalog!.loadConfigs());
    }
    final mcpPlugins = widget.sessions.pluginCatalogForMonitor(
      mcpMonitor,
      selectedScope: _mcpScope,
    );
    if (!identical(_mcpPlugins, mcpPlugins)) {
      _mcpPlugins = mcpPlugins;
      unawaited(mcpPlugins.refresh());
    }
    if (_skillsCatalog != null &&
        identical(_skillsCatalog!.transport.session, skillsMonitor.bridge) &&
        _skillsCatalog!.scopeKey == skillsScopeKey &&
        _skillsCatalog!.workspacePath == skillsWorkspacePath) {
      // Keep the existing catalog for this exact selected source.
    } else {
      _skillsCatalog?.dispose();
      _skillsCatalog = SkillsCatalog(
          transport: skillsMonitor.bridge.conversation(skillsMonitor.scope),
          scopeKey: skillsScopeKey,
          scope: skillsMonitor.scope,
          workspacePath: skillsWorkspacePath,
          workspaceIdentity: skillsMonitor.source.workspaceKey);
      unawaited(_skillsCatalog!.refresh());
    }
    _hooksWorkspaceMonitor ??= monitor;
    final hooksMonitor = _hooksWorkspaceMonitor!;
    final workspacePath = hooksMonitor.source.workspacePath ??
        (hooksMonitor.scope['workspacePath'] is String
            ? hooksMonitor.scope['workspacePath'] as String
            : null);
    final hooksScopeKey =
        '${hooksMonitor.source.deviceId}|${hooksMonitor.source.workspaceKey}';
    if (!(_hooksCatalog != null &&
        identical(_hooksCatalog!.session, hooksMonitor.bridge) &&
        _hooksCatalog!.scopeKey == hooksScopeKey &&
        _hooksCatalog!.workspacePath == workspacePath)) {
      _hooksCatalog?.dispose();
      _hooksCatalog = HooksCatalog(
          session: hooksMonitor.bridge,
          scope: hooksMonitor.scope,
          scopeKey: hooksScopeKey,
          workspacePath: workspacePath);
      unawaited(_hooksCatalog!.refresh());
    }
    final hooksPlugins = widget.sessions.pluginCatalogForMonitor(
      hooksMonitor,
      selectedScope: _hooksScopeKey == 'user' ? 'user' : 'workspace',
    );
    if (!identical(_hooksPlugins, hooksPlugins)) {
      _hooksPlugins = hooksPlugins;
      unawaited(hooksPlugins.refresh());
    }
    _subagentsWorkspaceMonitor ??= monitor;
    if (!(_subagentsCatalog != null &&
        identical(_subagentsCatalog!.session, monitor.bridge) &&
        _subagentsCatalog!.scopeKey == scopeKey &&
        _subagentsCatalog!.workspacePath == workspacePath)) {
      _subagentsCatalog?.dispose();
      _subagentsCatalog = SubagentsCatalog(
          session: monitor.bridge,
          scope: monitor.scope,
          scopeKey: scopeKey,
          workspacePath: workspacePath,
          scopeKind: 'user');
      unawaited(_subagentsCatalog!.refresh());
    }
    _commandsWorkspaceMonitor ??= monitor;
    if (!(_commandsCatalog != null &&
        identical(_commandsCatalog!.session, monitor.bridge) &&
        _commandsCatalog!.scopeKey == scopeKey &&
        _commandsCatalog!.workspacePath == workspacePath)) {
      _commandsCatalog?.dispose();
      _commandsCatalog = CommandsCatalog(
          session: monitor.bridge,
          scope: monitor.scope,
          scopeKey: scopeKey,
          workspacePath: workspacePath,
          scopeKind: 'user',
          pluginCatalog: _pluginsCatalog);
      unawaited(_commandsCatalog!.refresh());
    }
    if (!(_subagentsModelProviders != null &&
        identical(_subagentsModelProviders!.session, monitor.bridge) &&
        _subagentsModelProviders!.scopeKey == scopeKey)) {
      _subagentsModelProviders?.dispose();
      _subagentsModelProviders =
          ModelProvidersCatalog(session: monitor.bridge, scopeKey: scopeKey);
      unawaited(_subagentsModelProviders!.refresh());
    }
    if (!(_modelProviders != null &&
        identical(_modelProviders!.session, monitor.bridge) &&
        _modelProviders!.scopeKey == scopeKey)) {
      _modelProviders?.dispose();
      _modelProviders =
          ModelProvidersCatalog(session: monitor.bridge, scopeKey: scopeKey);
      unawaited(_modelProviders!.refresh());
    }
    if (!(_modelConnectivity != null &&
        identical(_modelConnectivity!.session, monitor.bridge) &&
        _modelConnectivity!.scopeKey == scopeKey)) {
      _modelConnectivity?.dispose();
      _modelConnectivity = ModelConnectivityController.withCaptcha(
        session: monitor.bridge,
        scopeKey: scopeKey,
        captcha: ModelCaptchaService.fromSession(
          session: monitor.bridge,
          languageProvider: () => widget.preferences.language == 'system'
              ? WidgetsBinding.instance.platformDispatcher.locale.languageCode
              : widget.preferences.language,
        ),
      );
    }
    // The plan summary card reuses the E2.1 read-only pricing catalog; it is
    // created lazily per scope when a provider detail is shown.
    if (_upgradeCatalog == null ||
        !_upgradeCatalog!.scopeKey.startsWith(scopeKey)) {
      _upgradeCatalog?.dispose();
      _upgradeCatalog = CodingPlanUpgradeCatalog(
          session: monitor.bridge,
          transport: monitor.bridge.conversation(monitor.scope),
          scopeKey: scopeKey);
    }
    // Official settings sidebar shows the connected account at the bottom.
    unawaited(() async {
      try {
        final profile = await RemoteProfile.load(monitor.bridge);
        if (mounted) setState(() => _profile = profile);
      } catch (_) {
        /* The sidebar stays usable without account metadata. */
      }
    }());
  }

  List<SubagentModelOption> _subagentModelOptions() {
    final providers =
        _subagentsModelProviders?.items ?? const <ModelProviderEntry>[];
    final options = <SubagentModelOption>[];
    final seen = <String>{};
    for (final provider in providers) {
      for (final model in provider.models) {
        final value = '${provider.id}/${model.id}';
        if (value.isEmpty || !seen.add(value)) continue;
        options.add(SubagentModelOption(
          value: value,
          label: '${provider.name} · ${model.name}',
          thoughtLevels: model.reasoningLevels,
        ));
      }
    }
    return options;
  }

  List<SubagentScopeOption> _subagentScopeOptions() {
    final monitor = _subagentsWorkspaceMonitor ?? widget.remoteMonitor;
    final catalog = _subagentsCatalog;
    if (monitor == null || catalog == null) return const [];
    final currentIdentity =
        '${monitor.source.deviceId}|${monitor.source.workspaceKey}';
    final workspaces = buildSettingsScopeOptions(
      widget.sessions,
      current: monitor,
    );
    return [
      SubagentScopeOption(
        key: 'user',
        label: uiText(context, '用户', 'User'),
        scope: 'user',
        identity: monitor.scope,
        workspacePath: monitor.source.workspacePath ??
            (monitor.scope['workspacePath'] is String
                ? monitor.scope['workspacePath'] as String
                : null),
      ),
      for (final option in workspaces)
        SubagentScopeOption(
          key: option.identity,
          label: option.label,
          scope: 'workspace',
          identity: option.scope,
          workspacePath: option.workspacePath,
          catalog: option.identity == currentIdentity &&
                  catalog.scopeKind == 'workspace'
              ? catalog
              : null,
        ),
    ];
  }

  Future<SubagentsCatalog?> _selectSubagentsWorkspace(
      SubagentScopeOption option) async {
    final generation = ++_subagentsWorkspaceSelectionGeneration;
    var monitor = _subagentsScopeMonitorFor(option);
    if (monitor == null) {
      final scopeOption = buildSettingsScopeOptions(
        widget.sessions,
        current: widget.remoteMonitor,
      ).where((candidate) => candidate.identity == option.key).firstOrNull;
      if (scopeOption == null) return null;
      try {
        monitor = await widget.sessions.openWorkspace(
          scopeOption.device,
          scopeOption.workspaceKey,
          scopeOption.scope,
        );
      } catch (value) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(value.toString())));
        }
        return null;
      }
    }
    if (!mounted || generation != _subagentsWorkspaceSelectionGeneration) {
      return null;
    }
    final identity =
        '${monitor.source.deviceId}|${monitor.source.workspaceKey}';
    if (option.key != 'user' && identity != option.key) return null;
    final path = option.workspacePath ??
        monitor.source.workspacePath ??
        (monitor.scope['workspacePath'] is String
            ? monitor.scope['workspacePath'] as String
            : null);
    _subagentsWorkspaceMonitor = monitor;
    final targetKind = option.scope == 'workspace' ? 'workspace' : 'user';
    if (!(_subagentsCatalog != null &&
        identical(_subagentsCatalog!.session, monitor.bridge) &&
        _subagentsCatalog!.scopeKey == identity)) {
      _subagentsCatalog?.dispose();
      _subagentsCatalog = SubagentsCatalog(
        session: monitor.bridge,
        scope: monitor.scope,
        scopeKey: identity,
        workspacePath: path,
        scopeKind: targetKind,
      );
    } else {
      _subagentsCatalog!.updateScope(
        nextScope: monitor.scope,
        nextWorkspacePath: path,
        nextScopeKey: identity,
        nextScopeKind: targetKind,
      );
    }
    if (!(_subagentsModelProviders != null &&
        identical(_subagentsModelProviders!.session, monitor.bridge) &&
        _subagentsModelProviders!.scopeKey == identity)) {
      _subagentsModelProviders?.dispose();
      _subagentsModelProviders =
          ModelProvidersCatalog(session: monitor.bridge, scopeKey: identity);
    }
    final catalog = _subagentsCatalog!;
    final providers = _subagentsModelProviders!;
    await Future.wait([catalog.refresh(), providers.refresh()]);
    if (!mounted || generation != _subagentsWorkspaceSelectionGeneration) {
      return null;
    }
    setState(() {});
    return catalog;
  }

  WorkspaceMonitor? _subagentsScopeMonitorFor(SubagentScopeOption option) {
    if (option.key == 'user') return _subagentsWorkspaceMonitor;
    return buildSettingsScopeOptions(widget.sessions,
            current: widget.remoteMonitor)
        .where((candidate) => candidate.identity == option.key)
        .firstOrNull
        ?.monitor;
  }

  List<CommandScopeOption> _commandScopeOptions() {
    final monitor = _commandsWorkspaceMonitor ?? widget.remoteMonitor;
    final catalog = _commandsCatalog;
    if (monitor == null || catalog == null) return const [];
    final workspaces = buildSettingsScopeOptions(
      widget.sessions,
      current: monitor,
    );
    return [
      CommandScopeOption(
        key: 'user',
        label: uiText(context, '用户', 'User'),
        scope: 'user',
        identity: monitor.scope,
      ),
      for (final option in workspaces)
        CommandScopeOption(
          key: option.identity,
          label: option.label,
          scope: 'project',
          identity: option.scope,
          workspacePath: option.workspacePath,
          catalog: null,
        ),
    ];
  }

  Future<CommandsCatalog?> _selectCommandsWorkspace(
      CommandScopeOption option) async {
    final generation = ++_commandsWorkspaceSelectionGeneration;
    var monitor = option.key == 'user' ? _commandsWorkspaceMonitor : null;
    final scopeOptions = buildSettingsScopeOptions(
      widget.sessions,
      current: widget.remoteMonitor,
    );
    final selected = option.key == 'user'
        ? null
        : scopeOptions
            .where((candidate) => candidate.identity == option.key)
            .firstOrNull;
    if (monitor == null && selected != null) {
      monitor = selected.monitor;
      if (monitor == null) {
        try {
          monitor = await widget.sessions.openWorkspace(
            selected.device,
            selected.workspaceKey,
            selected.scope,
          );
        } catch (value) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(value.toString())));
          }
          return null;
        }
      }
    }
    if (!mounted || generation != _commandsWorkspaceSelectionGeneration) {
      return null;
    }
    if (monitor == null) return null;
    final identity =
        '${monitor.source.deviceId}|${monitor.source.workspaceKey}';
    if (option.key != 'user' && option.key != identity) return null;
    final path = option.workspacePath ??
        monitor.source.workspacePath ??
        (monitor.scope['workspacePath'] is String
            ? monitor.scope['workspacePath'] as String
            : null);
    _commandsWorkspaceMonitor = monitor;
    final targetKind = option.scope == 'project' ? 'project' : 'user';
    final plugins = widget.sessions.pluginCatalogForMonitor(
      monitor,
      selectedScope: targetKind == 'project' ? 'workspace' : 'user',
    );
    if (!(_commandsCatalog != null &&
        identical(_commandsCatalog!.session, monitor.bridge) &&
        _commandsCatalog!.scopeKey == identity)) {
      _commandsCatalog?.dispose();
      _commandsCatalog = CommandsCatalog(
        session: monitor.bridge,
        scope: monitor.scope,
        scopeKey: identity,
        workspacePath: path,
        scopeKind: targetKind,
        pluginCatalog: plugins,
      );
      unawaited(plugins.refresh());
    } else {
      _commandsCatalog!.updatePluginCatalog(plugins);
      _commandsCatalog!.updateScope(
        nextScope: monitor.scope,
        nextScopeKey: identity,
        nextWorkspacePath: path,
        nextScopeKind: targetKind,
      );
      unawaited(plugins.refresh());
    }
    final catalog = _commandsCatalog!;
    await catalog.refresh();
    if (!mounted || generation != _commandsWorkspaceSelectionGeneration) {
      return null;
    }
    setState(() {});
    return catalog;
  }

  /// Resolve an independent form target. It intentionally does not mutate the
  /// list catalog or list scope; a form may write to another workspace while
  /// the catalog behind the page remains on User/current workspace.
  Future<CommandFormTarget?> _resolveCommandFormTarget(
      CommandScopeOption option) async {
    final scopeOptions = buildSettingsScopeOptions(
      widget.sessions,
      current: widget.remoteMonitor,
    );
    WorkspaceMonitor? monitor;
    SettingsScopeOption? workspaceOption;
    if (option.key == 'user') {
      monitor = _commandsWorkspaceMonitor ?? widget.remoteMonitor;
    } else {
      workspaceOption = scopeOptions
          .where((candidate) => candidate.identity == option.key)
          .firstOrNull;
      monitor = workspaceOption?.monitor;
      if (monitor == null && workspaceOption != null) {
        try {
          monitor = await widget.sessions.openWorkspace(
            workspaceOption.device,
            workspaceOption.workspaceKey,
            workspaceOption.scope,
          );
        } catch (value) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(value.toString())));
          }
          return null;
        }
      }
    }
    if (!mounted || monitor == null) return null;
    final identity =
        '${monitor.source.deviceId}|${monitor.source.workspaceKey}';
    if (option.key != 'user' && identity != option.key) return null;
    final path = option.workspacePath ??
        workspaceOption?.workspacePath ??
        monitor.source.workspacePath ??
        (monitor.scope['workspacePath'] is String
            ? monitor.scope['workspacePath'] as String
            : null);
    final targetKind = option.scope == 'project' ? 'project' : 'user';
    final targetKey = '$identity|$targetKind';
    final plugins = widget.sessions.pluginCatalogForMonitor(
      monitor,
      selectedScope: targetKind == 'project' ? 'workspace' : 'user',
    );
    var catalog = _commandsFormTargets[targetKey];
    if (catalog == null ||
        !identical(catalog.session, monitor.bridge) ||
        catalog.workspacePath != path) {
      if (catalog != null) catalog.dispose();
      catalog = CommandsCatalog(
        session: monitor.bridge,
        scope: monitor.scope,
        scopeKey: identity,
        workspacePath: path,
        scopeKind: targetKind,
        pluginCatalog: plugins,
      );
      _commandsFormTargets[targetKey] = catalog;
    } else {
      catalog.updatePluginCatalog(plugins);
      catalog.updateScope(
        nextScope: monitor.scope,
        nextScopeKey: identity,
        nextWorkspacePath: path,
        nextScopeKind: targetKind,
      );
    }
    unawaited(plugins.refresh());
    await catalog.refresh();
    if (!mounted) return null;
    return CommandFormTarget(
      catalog: catalog,
      onComposerRefresh: () => _invalidateComposerPrep(scopeMonitor: monitor!),
    );
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _updateError = null;
    });
    try {
      final result = await checkForUpdates();
      if (mounted) setState(() => _update = result);
    } catch (_) {
      if (mounted) {
        setState(() => _updateError = uiText(
            context, '检查失败，请稍后重试', 'Could not check for updates. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<bool> _saveProviderModels(
    ModelProviderEntry provider,
    void Function(List<Map<String, dynamic>> models) update,
  ) async {
    final catalog = _modelProviders;
    if (catalog == null) return false;
    final models = [
      for (final model in provider.models) {...model.raw},
    ];
    update(models);
    final saved = await catalog.saveProviderModels(provider, models);
    // E1.3: saved model rows can change composer candidates; refresh the
    // prepared options only after the authoritative getAll confirms success.
    if (saved) _invalidateComposerPrep();
    return saved;
  }

  Future<void> _deleteProvider(ModelProviderEntry provider) async {
    final catalog = _modelProviders;
    if (catalog == null || !catalog.canDelete(provider)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uiText(dialogContext, '删除供应商“${provider.name}”？',
            'Delete provider "${provider.name}"?')),
        content: Text(uiText(
            dialogContext,
            '删除后将移除这条自定义 Provider 配置，当前设置页中的相关内容不会自动恢复。',
            'This removes the custom provider configuration. Related edits on the current settings page will not be restored automatically.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(uiText(dialogContext, '取消', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(uiText(dialogContext, '确认删除', 'Delete provider'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final deleted = await catalog.deleteProvider(provider);
    if (deleted) _invalidateComposerPrep();
  }

  Future<void> _createProvider() async {
    final catalog = _modelProviders;
    if (catalog == null) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ProviderCreateDialog(catalog: catalog),
    );
    if (created == true) _invalidateComposerPrep();
  }

  Future<void> _editProviderConfiguration(ModelProviderEntry provider) async {
    final catalog = _modelProviders;
    final connectivity = _modelConnectivity;
    final monitor = widget.remoteMonitor;
    if (catalog == null || connectivity == null) return;
    final gate = _modelProviderEditorGate(provider);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ModelProviderEditor(
          provider: provider,
          catalog: catalog,
          connectivity: connectivity,
          useChinese: Localizations.localeOf(context).languageCode == 'zh',
          readOnlyEndpoints: gate.readOnlyEndpoints,
          readOnlyApiKey: gate.readOnlyApiKey,
          hideConnectionSection: gate.hideConnectionSection,
          hideApiKeySection: gate.hideApiKeySection,
          nameEditable: gate.nameEditable,
          modelsReadOnly: gate.modelsReadOnly,
          modelsEditMode: gate.modelsEditMode,
          cleanupOnDispose: true,
          // Capture the source at editor creation. A later Settings scope
          // switch must not refresh whichever monitor happens to be current
          // when the delayed save/read-back finishes.
          onComposerRefresh: monitor == null
              ? null
              : () => unawaited(
                  widget.sessions.refreshComposerScopeForMonitor(monitor)),
          onCancel: () => Navigator.pop(dialogContext),
          onSaved: (_) {
            Navigator.pop(dialogContext);
          },
        ),
      ),
    );
  }

  /// Provider editor gates come from explicit catalog source/flags. Provider
  /// names and labels are never used to infer a plan or preset.
  _ModelProviderEditorGate _modelProviderEditorGate(
      ModelProviderEntry provider) {
    // These IDs are the official first-party provider enum. Keep the plan
    // split explicit: ordinary builtin:zai/bigmodel/zapi presets expose the
    // API-key path, while the purchased/start plan cards hide connection and
    // key sections and use entitlement-backed access.
    final officialPlan = const {
      'builtin:zai-start-plan',
      'builtin:zai-coding-plan',
      'builtin:bigmodel-start-plan',
      'builtin:bigmodel-coding-plan',
    }.contains(provider.id);
    final officialStartPlan = const {
      'builtin:zai-start-plan',
      'builtin:bigmodel-start-plan',
    }.contains(provider.id);
    final source = provider.source.trim().toLowerCase();
    final raw = provider.raw;
    final plan = officialPlan ||
        source == 'coding-plan' ||
        source == 'team-plan' ||
        raw['providerKind'] == 'coding-plan' ||
        raw['providerKind'] == 'team-plan';
    final builtinPreset = isBuiltinProviderId(provider.id) && !officialPlan;
    final preset = builtinPreset ||
        source == 'preset' ||
        (source == 'builtin' && !plan) ||
        raw['presetId'] is String;
    final startPlan = officialStartPlan ||
        raw['startPlanMode'] == true ||
        raw['modelEditMode'] == 'context-window-only';
    final hidePlanSections = plan;
    return _ModelProviderEditorGate(
      readOnlyEndpoints: raw['readOnlyEndpoints'] == true || plan || preset,
      readOnlyApiKey: raw['readOnlyApiKey'] == true || plan,
      nameEditable: raw['nameEditable'] != false && !plan && !preset,
      modelsReadOnly: raw['modelsReadOnly'] == true,
      hideConnectionSection: hidePlanSections,
      hideApiKeySection: hidePlanSections,
      modelsEditMode: raw['modelsEditMode'] is String
          ? raw['modelsEditMode'] as String
          : startPlan
              ? 'context-window-only'
              : null,
    );
  }

  Future<void> _reorderProvider(
    ModelProviderEntry provider,
    int delta,
  ) async {
    final catalog = _modelProviders;
    if (catalog == null) return;
    final moved = await catalog.reorderProvider(provider, delta);
    if (moved) _invalidateComposerPrep();
  }

  Widget _modelRow(
    BuildContext context,
    InkTokens ink,
    ModelProviderEntry provider,
    int index,
  ) {
    final listenable = _modelConnectivity ?? _modelProviders!;
    return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          final model = provider.models[index];
          final busy = _modelProviders!.isSaving(provider.id);
          final error = _modelProviders!.errorOperation(provider.id) == 'save'
              ? _modelProviders!.saveError(provider.id)
              : null;
          final connectivity = _modelConnectivity;
          final editorGate = _modelProviderEditorGate(provider);
          final attempt = connectivity?.attemptFor(provider.id, model.id);
          final outcome = attempt?.outcome;
          // Official model row (js-1 3985k render + ROG capture): a bordered
          // id box holding the mono name plus the context badge (and the
          // bordered vision pill when inputs go beyond text), then the ghost
          // unplug test button, edit, delete. The test result renders as an
          // official pill below the row, never inside the button.
          final familyProvider = isFamilyProviderId(provider.id);
          String? contextBadge;
          if (model.contextWindow != null) {
            final window = model.contextWindow!;
            contextBadge = window >= 1000000
                ? '${window % 1000000 == 0 ? window ~/ 1000000 : (window / 1000000).toStringAsFixed(1)}M'
                : window >= 1000
                    ? '${window % 1000 == 0 ? window ~/ 1000 : (window / 1000).toStringAsFixed(0)}K'
                    : '$window';
          }
          Widget planTag(String label, {bool bordered = false}) => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                  color: ink.surface,
                  border: bordered ? Border.all(color: ink.border) : null,
                  borderRadius: BorderRadius.circular(999)),
              child: Text(label,
                  style: TextStyle(fontSize: 11, color: ink.subtlest)));
          final planHeadersAvailable =
              connectivity?.dynamicHeadersResolver != null &&
                  isZcodePlanProvider(provider, provider.raw);
          final useChinese =
              Localizations.localeOf(context).languageCode == 'zh';
          return Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                            border: Border.all(color: ink.border),
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          Expanded(
                              child: Text(model.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontFamily: 'monospace'))),
                          if (familyProvider)
                            for (final modality in model.inputModalities)
                              if (modality == 'image') ...[
                                const SizedBox(width: 6),
                                planTag(uiText(context, '视觉', 'Vision'),
                                    bordered: true),
                              ],
                          if (contextBadge != null) ...[
                            const SizedBox(width: 6),
                            planTag(contextBadge),
                          ],
                        ]))),
                ModelConnectivityButton(
                  modelId: model.id,
                  hasApiKey: provider.hasApiKey,
                  allowApiKeyless: planHeadersAvailable,
                  pending: attempt?.pending == true,
                  outcome: outcome,
                  onTest: connectivity == null
                      ? null
                      : () => _testModelConnectivity(provider, model,
                          controller: connectivity),
                ),
                if (editorGate.modelsEditMode != 'read-only')
                  IconButton(
                    tooltip: uiText(context, '编辑', 'Edit'),
                    onPressed: busy
                        ? null
                        : () =>
                            unawaited(_editProviderModel(provider, model)),
                    icon: const LucideIcon('pencil', size: 16),
                  ),
                if (provider.source == 'custom' &&
                    !familyProvider &&
                    editorGate.modelsEditMode != 'context-window-only')
                  IconButton(
                    tooltip: uiText(context, '删除', 'Delete'),
                    onPressed: busy
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: Text(uiText(dialogContext, '删除模型？',
                                    'Delete model?')),
                                content: Text(model.name),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(
                                          dialogContext, false),
                                      child: Text(uiText(dialogContext,
                                          '取消', 'Cancel'))),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(
                                          dialogContext, true),
                                      child: Text(uiText(dialogContext,
                                          '删除', 'Delete'))),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await _saveProviderModels(provider,
                                  (current) {
                                current.removeAt(index);
                              });
                            }
                          },
                    icon: const LucideIcon('trash-2', size: 16),
                  ),
              ]),
              if (outcome != null)
                Padding(
                    padding: const EdgeInsets.only(left: 10, top: 4),
                    child: ModelConnectivityResultPill(
                        outcome: outcome, useChinese: useChinese)),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    uiText(
                        context, '模型保存失败：$error', 'Model save failed: $error'),
                    style: TextStyle(fontSize: 12, color: ink.diffRemoved),
                  ),
                ),
            ]),
          );
        });
  }

  Future<void> _testModelConnectivity(
    ModelProviderEntry provider,
    ModelEntry model, {
    Map<String, dynamic>? draft,
    ModelConnectivityController? controller,
  }) async {
    final connectivity = controller ?? _modelConnectivity;
    if (connectivity == null) return;
    await connectivity.testModelConnectivity(
      provider: provider,
      model: model,
      draft: draft,
    );
  }

  Future<void> _editProviderModel(
    ModelProviderEntry provider,
    ModelEntry? model,
  ) async {
    final connectivity = _modelConnectivity;
    if (connectivity == null) return;
    final originalIndex = model == null
        ? -1
        : provider.models.indexWhere((item) => identical(item, model));
    final gate = _modelProviderEditorGate(provider);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ModelEntryEditor(
        provider: provider,
        model: model,
        connectivity: connectivity,
        useChinese: Localizations.localeOf(context).languageCode == 'zh',
        readOnly: gate.modelsReadOnly || gate.modelsEditMode == 'read-only',
        editMode: gate.modelsEditMode ?? 'full',
        onCancel: () => Navigator.pop(dialogContext),
        onCommit: (modelRaw) async {
          return _saveProviderModels(provider, (current) {
            if (originalIndex >= 0 && originalIndex < current.length) {
              current[originalIndex] = modelRaw;
            } else {
              current.add(modelRaw);
            }
          });
        },
        onSaved: () => Navigator.pop(dialogContext),
      ),
    );
  }

  void _openPluginManager() {
    unawaited(_openPluginManagerFlow());
  }

  Future<void> _openPluginManagerFlow() async {
    final monitor = _pluginsWorkspaceMonitor ?? widget.remoteMonitor;
    if (monitor == null) return;
    final catalog = _pluginsCatalog ??
        widget.sessions.pluginCatalogForMonitor(
          monitor,
          selectedScope: _pluginsScope,
        );
    _pluginsCatalog = catalog;
    unawaited(catalog.refresh());
    final page = MaterialPageRoute<SettingsNavigationResult>(
        builder: (pageContext) => Scaffold(
            appBar: AppBar(title: Text(uiText(context, '插件', 'Plugins'))),
            body: SafeArea(
                top: false,
                child: PluginMarketplace(
                    catalog: catalog,
                    onUse: (_) => Navigator.pop(pageContext),
                    onUsePrompt: (draft) =>
                        _preparePluginUseDraft(draft, monitor, pageContext)))));
    final result =
        await Navigator.push<SettingsNavigationResult>(context, page);
    if (!mounted || result == null) return;
    // The marketplace is a child route. Forward the typed target to the
    // SettingsCenter caller so showSettingsCenter can reopen the exact
    // WorkspaceShell draft without creating a second composer route.
    Navigator.of(context).pop(result);
  }

  List<SettingsScopeOption> _pluginsScopeOptions() {
    final monitor = _pluginsWorkspaceMonitor ?? widget.remoteMonitor;
    return buildSettingsScopeOptions(widget.sessions, current: monitor);
  }

  Future<void> _selectPluginsWorkspace(SettingsScopeOption option) async {
    final generation = ++_pluginsWorkspaceSelectionGeneration;
    final requestedIdentity = option.identity;
    var monitor = option.monitor;
    if (monitor == null) {
      try {
        monitor = await widget.sessions
            .openWorkspace(option.device, option.workspaceKey, option.scope);
      } catch (value) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(value.toString())));
        }
        return;
      }
    }
    if (!mounted || generation != _pluginsWorkspaceSelectionGeneration) return;
    if ('${monitor.source.deviceId}|${monitor.source.workspaceKey}' !=
        requestedIdentity) {
      return;
    }
    final catalog = widget.sessions.pluginCatalogForMonitor(
      monitor,
      selectedScope: _pluginsScope,
    );
    _pluginsWorkspaceMonitor = monitor;
    _pluginsWorkspaceScope = option;
    _pluginsCatalog = catalog;
    unawaited(catalog.refresh());
    setState(() {});
  }

  void _selectPluginConfigScope(String value) {
    if (!const ['user', 'workspace'].contains(value) ||
        value == _pluginsScope) {
      return;
    }
    final monitor = _pluginsWorkspaceMonitor ?? widget.remoteMonitor;
    setState(() => _pluginsScope = value);
    if (monitor == null) return;
    final catalog = widget.sessions.pluginCatalogForMonitor(
      monitor,
      selectedScope: value,
    );
    _pluginsCatalog = catalog;
    unawaited(catalog.refresh());
  }

  Future<void> _openMcpImport() async {
    final monitor = _mcpWorkspaceMonitor ?? widget.remoteMonitor;
    if (monitor == null) return;
    final importGeneration = _mcpWorkspaceSelectionGeneration;
    final importMonitor = monitor;
    final workspacePath = monitor.source.workspacePath ??
        (monitor.scope['workspacePath'] is String
            ? monitor.scope['workspacePath'] as String
            : null);
    await SettingsImportDialog.show(
      context,
      service: ChannelSettingsSyncService(monitor.bridge),
      category: 'mcpServers',
      workspacePath: workspacePath,
      workspaceIdentity: monitor.scope['workspaceIdentity'] is String
          ? monitor.scope['workspaceIdentity'] as String
          : null,
      onImported: () async {
        if (!mounted ||
            importGeneration != _mcpWorkspaceSelectionGeneration ||
            !identical(
                _mcpWorkspaceMonitor ?? widget.remoteMonitor, importMonitor)) {
          return;
        }
        await _mcpCatalog?.loadConfigs(force: true);
        if (mounted && importGeneration == _mcpWorkspaceSelectionGeneration) {
          _invalidateComposerPrep(scopeMonitor: importMonitor);
        }
      },
    );
  }

  Future<void> _openMcpAuthorizationUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw StateError('MCP authorization URL is invalid');
    }
    try {
      final opened = await const MethodChannel('zcode_remote/platform')
          .invokeMethod<Object?>('openExternalUrl', {'url': url});
      if (opened == false) {
        throw StateError('External browser could not open URL');
      }
    } on MissingPluginException {
      throw StateError('External browser is unavailable on this platform');
    }
  }

  void _selectSkillsConfigScope(String value) {
    if (!const ['user', 'workspace'].contains(value) || value == _skillsScope) {
      return;
    }
    final monitor = _skillsWorkspaceMonitor ?? widget.remoteMonitor;
    setState(() => _skillsScope = value);
    if (monitor == null) return;
    final plugins = widget.sessions.pluginCatalogForMonitor(
      monitor,
      selectedScope: value,
    );
    _skillsPlugins = plugins;
    unawaited(plugins.refresh());
  }

  Future<void> _selectSkillsWorkspace(SettingsScopeOption option) async {
    final generation = ++_skillsWorkspaceSelectionGeneration;
    final requestedIdentity = option.identity;
    var monitor = option.monitor;
    if (monitor == null) {
      try {
        monitor = await widget.sessions
            .openWorkspace(option.device, option.workspaceKey, option.scope);
      } catch (value) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(value.toString())));
        }
        return;
      }
    }
    if (!mounted || generation != _skillsWorkspaceSelectionGeneration) return;
    final resolvedIdentity =
        '${monitor.source.deviceId}|${monitor.source.workspaceKey}';
    if (resolvedIdentity != requestedIdentity) return;
    final workspacePath = monitor.source.workspacePath ??
        (monitor.scope['workspacePath'] is String
            ? monitor.scope['workspacePath'] as String
            : option.workspacePath);
    _skillsWorkspaceMonitor = monitor;
    _skillsWorkspaceScope = option;
    _skillsCatalog?.dispose();
    _skillsCatalog = SkillsCatalog(
      transport: monitor.bridge.conversation(monitor.scope),
      scopeKey: resolvedIdentity,
      scope: monitor.scope,
      workspacePath: workspacePath,
      workspaceIdentity: monitor.source.workspaceKey,
    );
    _skillsPlugins = widget.sessions.pluginCatalogForMonitor(
      monitor,
      selectedScope: _skillsScope,
    );
    unawaited(_skillsPlugins!.refresh());
    unawaited(_skillsCatalog!.refresh());
    setState(() {});
  }

  Future<void> _selectMcpWorkspace(SettingsScopeOption option) async {
    final generation = ++_mcpWorkspaceSelectionGeneration;
    final requestedIdentity = option.identity;
    var monitor = option.monitor;
    if (monitor == null) {
      try {
        monitor = await widget.sessions
            .openWorkspace(option.device, option.workspaceKey, option.scope);
      } catch (value) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(value.toString())));
        }
        return;
      }
    }
    if (!mounted || generation != _mcpWorkspaceSelectionGeneration) return;
    final resolvedIdentity =
        '${monitor.source.deviceId}|${monitor.source.workspaceKey}';
    if (resolvedIdentity != requestedIdentity) return;
    _mcpWorkspaceMonitor = monitor;
    _mcpWorkspaceScope = option;
    final workspacePath = monitor.source.workspacePath ??
        (monitor.scope['workspacePath'] is String
            ? monitor.scope['workspacePath'] as String
            : option.workspacePath);
    _mcpCatalog?.dispose();
    _mcpCatalog = McpCatalog(
      session: monitor.bridge,
      scope: monitor.scope,
      scopeKey: '${monitor.source.deviceId}|${monitor.source.workspaceKey}',
      workspacePath: workspacePath,
      onConfigurationChanged: () => _invalidateComposerPrep(
        scopeMonitor: monitor!,
      ),
    );
    _mcpPlugins = widget.sessions.pluginCatalogForMonitor(
      monitor,
      selectedScope: _mcpScope,
    );
    unawaited(_mcpPlugins!.refresh());
    unawaited(_mcpCatalog!.loadConfigs());
    setState(() {});
  }

  void _selectMcpConfigScope(String value) {
    if (!const ['user', 'workspace'].contains(value) || value == _mcpScope) {
      return;
    }
    final monitor = _mcpWorkspaceMonitor ?? widget.remoteMonitor;
    setState(() => _mcpScope = value);
    if (monitor == null) return;
    final plugins = widget.sessions.pluginCatalogForMonitor(
      monitor,
      selectedScope: value,
    );
    _mcpPlugins = plugins;
    unawaited(plugins.refresh());
  }

  List<SettingsScopeOption> _hooksScopeOptions() {
    final monitor = _hooksWorkspaceMonitor ?? widget.remoteMonitor;
    return buildSettingsScopeOptions(widget.sessions, current: monitor);
  }

  Future<bool> _selectHooksScope(String scopeKey) async {
    if (scopeKey == 'user') {
      ++_hooksWorkspaceSelectionGeneration;
      final monitor = widget.remoteMonitor;
      if (monitor != null) {
        final plugins = widget.sessions.pluginCatalogForMonitor(
          monitor,
          selectedScope: 'user',
        );
        if (!identical(_hooksPlugins, plugins)) {
          _hooksPlugins = plugins;
          unawaited(plugins.refresh());
        }
      }
      if (!mounted) return false;
      setState(() {
        _hooksScopeKey = 'user';
      });
      return true;
    }
    final option = _hooksScopeOptions()
        .where((candidate) => candidate.identity == scopeKey)
        .firstOrNull;
    if (option == null) return false;
    final generation = ++_hooksWorkspaceSelectionGeneration;
    var monitor = option.monitor;
    if (monitor == null) {
      try {
        monitor = await widget.sessions
            .openWorkspace(option.device, option.workspaceKey, option.scope);
      } catch (value) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(value.toString())));
        }
        return false;
      }
    }
    if (!mounted || generation != _hooksWorkspaceSelectionGeneration) {
      return false;
    }
    if ('${monitor.source.deviceId}|${monitor.source.workspaceKey}' !=
        option.identity) {
      return false;
    }
    final workspacePath = monitor.source.workspacePath ??
        (monitor.scope['workspacePath'] is String
            ? monitor.scope['workspacePath'] as String
            : option.workspacePath);
    _hooksWorkspaceMonitor = monitor;
    _hooksScopeKey = option.identity;
    _hooksCatalog?.dispose();
    _hooksCatalog = HooksCatalog(
      session: monitor.bridge,
      scope: monitor.scope,
      scopeKey: option.identity,
      workspacePath: workspacePath,
    );
    _hooksPlugins = widget.sessions.pluginCatalogForMonitor(
      monitor,
      selectedScope: 'workspace',
    );
    unawaited(_hooksCatalog!.refresh());
    unawaited(_hooksPlugins!.refresh());
    setState(() {});
    return true;
  }

  String _embeddedSourceKey(WorkspaceMonitor monitor) =>
      '${identityHashCode(monitor.bridge)}|${monitor.source.deviceId}|${monitor.source.workspaceKey}';

  Widget _embeddedDevices() {
    if (!_devicesVisited) return const SizedBox.shrink();
    return TickerMode(
        enabled: _section == 'devices',
        child: Offstage(
            offstage: _section != 'devices',
            child: DeviceDirectory(
                key: const ValueKey('settings-embedded-devices'),
                embedded: true,
                store: widget.sessions.store,
                sessions: widget.sessions,
                onOpen: widget.onOpenDevice ??
                    (device) async {
                      widget.onManageDevices();
                    },
                onSettings: () => _selectSection('general'))));
  }

  Widget _embeddedUsage(BuildContext context, InkTokens ink) {
    if (!_usageVisited) return const SizedBox.shrink();
    final monitor = widget.remoteMonitor;
    if (monitor == null) {
      return TickerMode(
          enabled: _section == 'usage',
          child: Offstage(
              offstage: _section != 'usage',
              child:
                  Column(children: _remoteSettingsPlaceholder(context, ink))));
    }
    final transport = monitor.bridge.conversation(monitor.scope);
    final planSelection = widget.sessions.usagePlanSelectionFor(
        deviceId: monitor.source.deviceId,
        workspaceKey: monitor.source.workspaceKey,
        transport: transport,
        preferences: widget.preferences);
    final sourceKey = _embeddedSourceKey(monitor);
    return TickerMode(
        enabled: _section == 'usage',
        child: Offstage(
            offstage: _section != 'usage',
            child: UsagePage(
                key: ValueKey('settings-embedded-usage-$sourceKey'),
                sourceKey: sourceKey,
                embedded: true,
                active: _section == 'usage',
                showHeader: false,
                usage: planSelection.usage,
                planSelection: planSelection,
                onConfigurePlans: () => _selectSection('modelProvider'))));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.preferences,
      builder: (context, _) {
        final ink = ZInk.of(Theme.of(context).colorScheme);
        final labels = <String, (String, String, String)>{
          'general': ('sliders-horizontal', '常规', 'General'),
          'appearance': ('settings', '外观', 'Appearance'),
          'notifications': ('bell', '通知与上岛', 'Task notifications'),
          'devices': ('monitor', '设备', 'Devices'),
          'updates': ('package', '更新与关于', 'Updates and about'),
          'voice': ('sparkles', '语音模型', 'Voice models'),
          // Remote settings sections (official settings catalog, E1.2).
          // Each maps to a settingsService.update() field; RPC wire format
          // pending verification with real remote connection.
          'modelProvider': ('cpu', '模型设置', 'Model settings'),
          'plugins': ('blocks', '插件', 'Plugins'),
          'skills': ('graduation-cap', '技能', 'Skills'),
          'mcp': ('server', 'MCP 服务器', 'MCP Servers'),
          'subagents': ('bot', '子智能体', 'Subagents'),
          'commands': ('square-slash', '命令', 'Commands'),
          'hooks': ('anchor', '钩子', 'Hooks'),
          'memory': ('brain', '记忆', 'Memory'),
          'browser': ('globe', '浏览器控制', 'Browser control'),
          'indexing': ('database', '索引库', 'Indexing'),
          'usage': ('bar-chart-3', '使用统计', 'Usage stats'),
        };
        Widget item(String key) {
          final value = labels[key]!;
          return Material(
              color: _section == key ? ink.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _selectSection(key),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 32),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(mainAxisSize: MainAxisSize.max, children: [
                            LucideIcon(value.$1, size: 16, color: ink.subtlest),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(uiText(context, value.$2, value.$3),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14)))
                          ])))));
        }

        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final wideBreakpoint = 264 + 400 * textScale.clamp(1.0, 2.0);
        final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
        return Scaffold(
            // Desktop settings is a two-pane surface with its own back entry;
            // the compact route keeps the normal Material app-bar back stack.
            appBar: wide
                ? null
                : AppBar(title: Text(uiText(context, '设置', 'Settings'))),
            body: SafeArea(
                top: false,
                child: LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth >= wideBreakpoint;
                  final deviceSession = widget.remoteMonitor == null
                      ? null
                      : widget.sessions
                          .sessionOf(widget.remoteMonitor!.source.deviceId);
                  final connection = connectionStatusSnapshot(
                      deviceSession, widget.remoteMonitor?.bridge);
                  final remoteSection = {
                    'modelProvider',
                    'plugins',
                    'skills',
                    'mcp',
                    'subagents',
                    'commands',
                    'hooks',
                    'memory',
                    'browser',
                    'indexing',
                    'usage',
                  }.contains(_section);
                  final remoteUnavailable = widget.remoteMonitor != null &&
                      remoteSection &&
                      _section != 'mcp' &&
                      !connection.healthy;
                  final pageWidgets = <Widget>[
                    _embeddedDevices(),
                    _embeddedUsage(context, ink),
                    ..._content(context, ink),
                  ];
                  final gatedWidgets = AbsorbPointer(
                    absorbing: remoteUnavailable,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: pageWidgets),
                  );
                  final connectionBanner = widget.remoteMonitor == null
                      ? const SizedBox.shrink()
                      : ConnectionStatusBanner(
                          session: deviceSession,
                          bridge: widget.remoteMonitor!.bridge,
                          onReconnect: deviceSession?.reconnect,
                          onPairAgain: () async => widget.onManageDevices(),
                          onCancel: deviceSession?.cancelRecovery,
                        );
                  final hasPageTitle = true;
                  final content =
                      NotificationListener<ScrollMetricsNotification>(
                          onNotification: _restoreSectionFromMetrics,
                          child: ListView(
                              key: const ValueKey('usage-page-scroll'),
                              controller: _scrollControllerFor(_section),
                              padding: wide
                                  ? const EdgeInsets.fromLTRB(32, 44, 32, 32)
                                  : const EdgeInsets.fromLTRB(20, 20, 20, 28),
                              children: [
                                if (hasPageTitle)
                                  Text(
                                      uiText(context, labels[_section]!.$2,
                                          labels[_section]!.$3),
                                      style: TextStyle(
                                          fontSize: wide ? 28 : 20,
                                          fontWeight: FontWeight.w500,
                                          color: ink.text)),
                                if (hasPageTitle) const SizedBox(height: 24),
                                gatedWidgets,
                              ]));
                  if (!wide) {
                    return Column(children: [
                      Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          child: DropdownButton<String>(
                              isExpanded: true,
                              isDense: true,
                              value: _section,
                              items: [
                                for (final entry in labels.entries)
                                  DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(uiText(context,
                                          entry.value.$2, entry.value.$3))),
                                // Official 数据与统计 "引导" entry; the compact
                                // select opens the dialog instead of switching
                                // sections.
                                if (widget.remoteMonitor != null)
                                  DropdownMenuItem(
                                      value: '_onboarding',
                                      child: Text(uiText(
                                          context, '引导', 'Onboarding'))),
                              ],
                              onChanged: (value) {
                                if (value == '_onboarding') {
                                  unawaited(_openOnboardingDialog());
                                  return;
                                }
                                if (value != null) {
                                  _selectSection(value);
                                }
                              })),
                      const Divider(height: 1),
                      Expanded(
                          child: Column(children: [
                        connectionBanner,
                        Expanded(child: content),
                      ]))
                    ]);
                  }
                  return Row(children: [
                    Container(
                        width: 264,
                        color: ink.surface,
                        child: Column(children: [
                          Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 64, 12, 12),
                              child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () =>
                                          Navigator.of(context).maybePop(),
                                      child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 6),
                                          child: SizedBox(
                                              width: double.infinity,
                                              child: Row(children: [
                                                LucideIcon('arrow-left',
                                                    size: 16,
                                                    color: ink.subtlest),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                    child: Text(
                                                        uiText(context, '返回工作区',
                                                            'Back to workspace'),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                            fontSize: 13,
                                                            color:
                                                                ink.subtlest))),
                                              ])))))),
                          Expanded(
                              child: SingleChildScrollView(
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 0, 8, 72),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // Official order: basics, agent
                                        // capabilities, data/statistics. Local
                                        // extensions remain reachable in their own
                                        // trailing group.
                                        for (final group in const [
                                          (
                                            '基础设置',
                                            'Basics',
                                            <String>[
                                              'general',
                                              'appearance',
                                              'modelProvider',
                                              'browser',
                                            ]
                                          ),
                                          (
                                            'Agent 能力',
                                            'Agent capabilities',
                                            <String>[
                                              'memory',
                                              'subagents',
                                              'plugins',
                                              'mcp',
                                              'skills',
                                              'commands',
                                              'hooks',
                                            ]
                                          ),
                                          (
                                            '数据与统计',
                                            'Data and statistics',
                                            <String>['indexing', 'usage']
                                          ),
                                          (
                                            '客户端',
                                            'Client',
                                            <String>[
                                              'devices',
                                              'voice',
                                              'notifications',
                                              'updates',
                                            ]
                                          ),
                                        ]) ...[
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 10, top: 10, bottom: 4),
                                              child: Text(
                                                  uiText(context, group.$1,
                                                      group.$2),
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: ink.subtlest))),
                                          for (final key in group.$3) item(key),
                                          if (group.$1 == '数据与统计' &&
                                              widget.remoteMonitor != null)
                                            _onboardingNavItem(ink),
                                        ],
                                      ]))),
                          Container(
                              padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
                              // Keep the fixed footer opaque while the
                              // navigation list scrolls behind it.
                              decoration: BoxDecoration(color: ink.surface),
                              child: Row(children: [
                                CircleAvatar(
                                    radius: 16,
                                    backgroundImage: _profile?.avatarUrl == null
                                        ? null
                                        : NetworkImage(_profile!.avatarUrl!),
                                    child: _profile?.avatarUrl == null
                                        ? Text(
                                            _profile?.name.isNotEmpty == true
                                                ? _profile!
                                                    .name.characters.first
                                                : '?',
                                            style:
                                                const TextStyle(fontSize: 12))
                                        : null),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(
                                        _profile?.name ??
                                            uiText(
                                                context, '未登录', 'Signed out'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13))),
                                LucideIcon('settings',
                                    size: 16, color: ink.subtlest),
                              ])),
                        ])),
                    Expanded(
                        child: Column(children: [
                      connectionBanner,
                      Expanded(
                          // Official settings shell is a centered max-w-5xl
                          // (1024px) column (`mx-auto flex w-full max-w-5xl
                          // flex-col px-4 py-4 md:px-6 md:py-6`); the left
                          // 864 cap squeezed every settings page against the
                          // navigation rail.
                          child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 1024),
                                  child: SizedBox(
                                      width: double.infinity,
                                      child: content)))),
                    ]))
                  ]);
                })));
      });

  List<Widget> _content(BuildContext context, InkTokens ink) {
    final prefs = widget.preferences;
    switch (_section) {
      case 'general':
        return _generalContent(context, ink);
      case 'appearance':
        return [
          AppearanceSettingsPage(
            preferences: prefs,
            embedded: true,
          ),
        ];
      case 'notifications':
        return [
          // U26: the notification body renders inline in the settings right
          // pane (user requirement); the standalone page keeps the narrow
          // screen route.
          NotificationSettingsPage(
              key: const ValueKey('settings-embedded-notifications'),
              controller: widget.sessions.notifications,
              embedded: true),
        ];
      case 'devices':
        return const [];
      case 'modelProvider':
      case 'hooks':
      case 'memory':
      case 'browser':
      case 'indexing':
        return _remoteSettingsContent(context, ink, _section);
      case 'skills':
        return _skillsContent(context, ink);
      case 'mcp':
        return _mcpContent(context, ink);
      case 'subagents':
        return _subagentsContent(context, ink);
      case 'commands':
        return _commandsContent(context, ink);
      case 'plugins':
        return _pluginsContent(context, ink);
      case 'voice':
        return [VoiceModelManager()];
      case 'usage':
        return const [];
      default:
        return [
          Text('ZcodeRemote $appVersion ($appBuildNumber)',
              style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 20),
          SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title:
                  Text(uiText(context, '接收 Beta 更新', 'Receive beta updates')),
              value: updateChannelSettings.receiveBetaUpdates,
              onChanged: (value) async {
                await updateChannelSettings.setReceiveBetaUpdates(value);
                if (mounted) setState(() {});
              }),
          const SizedBox(height: 12),
          Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                  onPressed: _checking ? null : _checkUpdate,
                  child: Text(_checking
                      ? uiText(context, '正在检查…', 'Checking…')
                      : uiText(context, '检查更新', 'Check for updates')))),
          if (_updateError != null)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_updateError!,
                    style: TextStyle(color: ink.diffRemoved))),
          if (_update != null) ...[
            const SizedBox(height: 20),
            Text(_update!.isNewer
                ? uiText(context, '发现新版本 ${_update!.latestVersion}',
                    'New version ${_update!.latestVersion}')
                : uiText(context, '当前已是最新版本', 'You are up to date')),
            if (_update!.body?.trim().isNotEmpty == true)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(_update!.body!)),
            if (_update!.isNewer) ...[
              Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 8, children: [
                    TextButton(
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: _update!.releaseUrl));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(uiText(context, '下载页面地址已复制',
                                    'Download page copied'))));
                          }
                        },
                        child: Text(
                            uiText(context, '复制下载页面地址', 'Copy download page'))),
                    ListenableBuilder(
                        listenable: _downloader ?? Listenable.merge([]),
                        builder: (context, _) {
                          final dl = _downloader;
                          final prog = dl?.progress;
                          return FilledButton(
                              onPressed: _update!.assets.isEmpty ||
                                      (dl?.isBusy ?? false)
                                  ? null
                                  : () => _startDownload(context),
                              child: Text((prog?.state ==
                                          DownloadState.downloading ||
                                      prog?.state == DownloadState.verifying)
                                  ? uiText(context, '下载中…', 'Downloading…')
                                  : uiText(context, '下载 APK', 'Download APK')));
                        }),
                  ])),
              if (_downloader != null)
                ListenableBuilder(
                    listenable: _downloader!,
                    builder: (context, _) {
                      final prog = _downloader!.progress;
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (prog.state == DownloadState.downloading &&
                                prog.fraction != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: LinearProgressIndicator(
                                      value: prog.fraction)),
                            if (prog.state == DownloadState.verifying)
                              Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                      uiText(context, '校验中…', 'Verifying…'))),
                            if (prog.state == DownloadState.done &&
                                prog.filePath != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                      uiText(context, '已下载到 ${prog.filePath}',
                                          'Downloaded to ${prog.filePath}'),
                                      style: TextStyle(
                                          fontSize: 12, color: ink.subtlest))),
                            if (prog.state == DownloadState.failed &&
                                prog.error != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(prog.error!,
                                      style:
                                          TextStyle(color: ink.diffRemoved))),
                          ]);
                    }),
            ],
          ],
        ];
    }
  }

  List<Widget> _remoteSettingsContent(
      BuildContext context, InkTokens ink, String section) {
    // Hooks own their loadHooks/plugin-management projections. Rendering
    // them outside the generic setting snapshot keeps an empty or failed
    // setting.get response from hiding a valid hooks page.
    if (section == 'hooks') {
      final hooks = _hooksCatalog;
      final hooksMonitor = _hooksWorkspaceMonitor ?? widget.remoteMonitor;
      if (hooks == null || hooksMonitor == null) {
        return _remoteSettingsPlaceholder(context, ink);
      }
      final mutationMonitor = hooksMonitor;
      return [
        HooksSettingsPage(
          key: const ValueKey('settings-hooks-page'),
          catalog: hooks,
          pluginCatalog: _hooksPlugins,
          scopeOptions: _hooksScopeOptions(),
          selectedScopeKey: _hooksScopeKey,
          onScopeChanged: _selectHooksScope,
          onTrustHook: (request) async {
            final result = await hooks.grantWorkspaceHookTrust(
              request.hook,
              workspaceIdentity: request.workspaceIdentity,
            );
            return WorkspaceHookTrustResult(
              accepted: result['accepted'] == true,
              reasonCode: result['reasonCode'] is String
                  ? result['reasonCode'] as String
                  : null,
            );
          },
          onAfterMutation: () async {
            _invalidateComposerPrep(scopeMonitor: mutationMonitor);
          },
        ),
      ];
    }
    final controller = _remoteSettings;
    if (controller == null) {
      return _remoteSettingsPlaceholder(context, ink);
    }
    Widget view(ListenableBuilder listenable) => listenable;
    return [
      view(ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final snapshot = controller.snapshot;
            final children = <Widget>[];
            if (controller.status == RemoteSettingsStatus.loading) {
              children.add(const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(strokeWidth: 2)));
            } else if (controller.status == RemoteSettingsStatus.error) {
              children.addAll([
                Text(
                    uiText(context, '远端设置读取失败，请重试。',
                        'Could not read remote settings. Retry.'),
                    style: TextStyle(color: ink.diffRemoved)),
                const SizedBox(height: 12),
                Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                        onPressed: () => unawaited(controller.refresh()),
                        child: Text(uiText(context, '重试', 'Retry')))),
              ]);
            } else if (snapshot.isEmpty &&
                section != 'modelProvider' &&
                section != 'hooks') {
              children.add(Text(
                  uiText(
                      context, '远端没有返回设置数据。', 'No remote settings returned.'),
                  style: TextStyle(color: ink.subtlest)));
            } else if (section == 'modelProvider') {
              // Official ModelProviderSection (official-settings-model
              // screenshot): intro row with refresh, then a two-pane layout —
              // the left pane lists providers grouped into builtin/custom
              // groups with status dots and an add-provider action, the right
              // pane shows the selected provider detail (name + enabled
              // badge + connection mode + provider actions, model list with
              // add-model). Without a selected provider the detail pane
              // falls back to the family connection list so the verified
              // family write path keeps working on empty catalogs.
              final savingModes =
                  controller.isSaving('modelProviderFamilyModes') ||
                      controller.isSaving('modelProviderFamilyModes|'
                          'modelProviderFamilySelectedKeys');
              final failedModes =
                  controller.saveError('modelProviderFamilyModes') != null ||
                      controller.saveError('modelProviderFamilyModes|'
                              'modelProviderFamilySelectedKeys') !=
                          null;
              Widget connectionBlock() => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final family
                            in snapshot.providerFamilyModes.keys) ...[
                          const SizedBox(height: 8),
                          Builder(builder: (context) {
                            _ensureFamilyOptions(family);
                            final options = _familyOptions[family];
                            final current =
                                snapshot.providerFamilySelectedKeys[family] ??
                                    '';
                            FamilyConnectionOption? selected;
                            for (final option in options ?? const []) {
                              if (option.key == current) selected = option;
                            }
                            if (selected == null &&
                                snapshot.providerFamilyModes[family] ==
                                    'apiKey' &&
                                current == 'preset:builtin:$family') {
                              for (final option in options ?? const []) {
                                if (option.mode == 'apiKey') selected = option;
                              }
                            }
                            return _row(
                              '$family: '
                              '${selected?.label ?? snapshot.providerFamilySelectedKeys[family] ?? '--'}',
                              options == null
                                  ? Text(uiText(context, '连接方式读取中…',
                                      'Loading connection options…'))
                                  : DropdownButton<FamilyConnectionOption>(
                                      value: selected,
                                      underline: const SizedBox(),
                                      isExpanded: true,
                                      items: [
                                        for (final option in options)
                                          DropdownMenuItem(
                                              value: option,
                                              child: Text(option.label,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis))
                                      ],
                                      onChanged: savingModes
                                          ? null
                                          : (option) async {
                                              if (option == null) return;
                                              await _applyFamilyConnection(
                                                  family, option);
                                            }),
                            );
                          }),
                        ],
                        for (final family in snapshot.providerFamilyModes.keys)
                          if (_familyOptionsFailed.contains(family)) ...[
                            const SizedBox(height: 8),
                            Text(
                                uiText(context, '团队连接方式读取失败，仅显示基础连接方式。',
                                    'Team connection options are unavailable; basic entries are shown.'),
                                style: TextStyle(color: ink.subtlest)),
                          ],
                        if (failedModes) ...[
                          const SizedBox(height: 8),
                          Text(
                              uiText(context, '保存失败，已保留原设置。',
                                  'Save failed. The previous value is kept.'),
                              style: TextStyle(color: ink.diffRemoved)),
                          const SizedBox(height: 8),
                          OutlinedButton(
                              onPressed: savingModes
                                  ? null
                                  : () => unawaited(controller.updatePatch(
                                      (controller.lastAttempt(
                                                      'modelProviderFamilyModes|'
                                                      'modelProviderFamilySelectedKeys')
                                                  as Map?)
                                              ?.cast<String, Object?>() ??
                                          {
                                            'modelProviderFamilyModes':
                                                controller.lastAttempt(
                                                    'modelProviderFamilyModes')
                                          })),
                              child: Text(uiText(context, '重试', 'Retry'))),
                        ],
                      ]);
              children.addAll([
                Row(children: [
                  Expanded(
                      child: Text(
                          uiText(context, '管理自定义模型供应商，配置后可在聊天时选择使用。',
                              'Manage custom model providers; configured providers become selectable in chat.'),
                          style: TextStyle(color: ink.subtlest))),
                  if (_modelProviders != null)
                    IconButton(
                        tooltip: uiText(context, '刷新', 'Refresh'),
                        onPressed: () => unawaited(_modelProviders!.refresh()),
                        icon: const LucideIcon('refresh-cw', size: 15)),
                ]),
                const SizedBox(height: 12),
                if (_modelProviders == null)
                  Text(uiText(context, '目录未初始化。', 'Catalog not ready.'),
                      style: TextStyle(color: ink.subtlest))
                else
                  ListenableBuilder(
                      listenable: _modelProviders!,
                      builder: (context, _) {
                        final catalog = _modelProviders!;
                        if (catalog.status ==
                            ModelProviderCatalogStatus.loading) {
                          return Text(uiText(context, '加载中…', 'Loading…'),
                              style: TextStyle(color: ink.subtlest));
                        }
                        if (catalog.status ==
                            ModelProviderCatalogStatus.error) {
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    uiText(context, '读取失败。', 'Failed to load.'),
                                    style: TextStyle(color: ink.diffRemoved)),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                    onPressed: () =>
                                        unawaited(catalog.refresh()),
                                    child:
                                        Text(uiText(context, '重试', 'Retry'))),
                              ]);
                        }
                        final providers = catalog.items;
                        // Official nav grouping (`$Kt`): zhipu-family ids
                        // collapse into brand rows under the 智谱 group and
                        // never appear in the custom list (`fVt` id filter).
                        final familyEntries =
                            <String, List<ModelProviderEntry>>{};
                        final custom = <ModelProviderEntry>[];
                        for (final provider in providers) {
                          final family = zhipuFamilyOfId(provider.id);
                          if (family != null) {
                            familyEntries
                                .putIfAbsent(family.key, () => [])
                                .add(provider);
                          } else {
                            custom.add(provider);
                          }
                        }
                        // Official preset rows are domain-filtered
                        // (`Cqt`/providerFamilyDomain): a pinned domain hides
                        // the other family; ZAPI additionally requires its
                        // synced preset (`KQe` zapiEnabled proxy: a catalog
                        // entry must exist).
                        final domain = snapshot.providerFamilyDomain;
                        final visibleFamilies = [
                          for (final family in kZhipuFamilies)
                            if ((domain == null ||
                                    domain.isEmpty ||
                                    domain == family.key ||
                                    (domain != 'zai' &&
                                        domain != 'bigmodel')) &&
                                (familyEntries.containsKey(family.key) ||
                                    domain == family.key))
                              family
                        ];
                        String? selectedFamily = _selectedModelFamily;
                        ModelProviderEntry? selected;
                        if (selectedFamily == null) {
                          for (final provider in providers) {
                            if (provider.id == _selectedProviderId) {
                              selected = provider;
                            }
                          }
                        }
                        // Official default selection is the first nav item;
                        // the family row leads the list, then the first
                        // custom provider.
                        if (selectedFamily == null && selected == null) {
                          selectedFamily = visibleFamilies.firstOrNull?.key;
                          selected = custom.firstOrNull;
                        }
                        Widget providerTile(ModelProviderEntry provider) {
                          final isSelected = selectedFamily == null &&
                              provider.id == selected?.id;
                          return InkWell(
                              onTap: () => setState(() {
                                    _selectedProviderId = provider.id;
                                    _selectedModelFamily = null;
                                  }),
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                      color: isSelected
                                          ? ink.hover
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Row(children: [
                                    const LucideIcon('box', size: 15),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Text(provider.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis)),
                                    const SizedBox(width: 8),
                                    Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: provider.enabled
                                                ? ink.diffAdded
                                                : ink.subtlest)),
                                  ])));
                        }

                        Widget familyTile(ZhipuFamily family) {
                          final isSelected = selectedFamily == family.key;
                          final activeEntry = _familyActiveProviderEntry(
                              snapshot, family.key, familyEntries[family.key]);
                          return InkWell(
                              onTap: () => setState(() {
                                    _selectedModelFamily = family.key;
                                    _selectedProviderId = null;
                                  }),
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                      color: isSelected
                                          ? ink.hover
                                          : Colors.transparent,
                                      border: Border.all(
                                          color: isSelected
                                              ? ink.border
                                              : Colors.transparent),
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Row(children: [
                                    const LucideIcon('box', size: 15),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Text(family.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis)),
                                    const SizedBox(width: 8),
                                    Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: (activeEntry?.enabled ??
                                                    false)
                                                ? ink.diffAdded
                                                : ink.subtlest)),
                                  ])));
                        }

                        // Provider list content. In the two-pane layout it
                        // renders inside the single official container (the
                        // vertical divider supplies the separation); narrow
                        // widths keep the standalone framed card.
                        Widget leftPaneContent = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (visibleFamilies.isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            12, 10, 12, 4),
                                        child: Text(
                                            uiText(context, '智谱', 'Zhipu'),
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: ink.subtlest))),
                                  for (final family in visibleFamilies)
                                    familyTile(family),
                                  if (custom.isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            12, 10, 12, 4),
                                        child: Text(
                                            uiText(context, '自定义供应商',
                                                'Custom providers'),
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: ink.subtlest))),
                                  for (final provider in custom)
                                    providerTile(provider),
                                  Padding(
                                      padding:
                                          const EdgeInsets.fromLTRB(8, 4, 8, 8),
                                      child: TextButton.icon(
                                          onPressed: _modelProviders!
                                                  .isCreatingProvider
                                              ? null
                                              : () =>
                                                  unawaited(_createProvider()),
                                          icon: const LucideIcon('plus',
                                              size: 15),
                                          label: Text(
                                              uiText(context, '添加供应商',
                                                  'Add provider'),
                                              style: const TextStyle(
                                                  fontSize: 13)))),
                                ]);
                        // Official family detail (`rqt` selection redirect):
                        // the brand header carries the enabled pill and the
                        // connection-mode select; the plan card and model
                        // list describe the ACTIVE connection's provider.
                        Widget familyDetailPane() {
                          final family = visibleFamilies.firstWhere(
                              (candidate) => candidate.key == selectedFamily);
                          final active = _familyActiveProviderEntry(
                              snapshot, family.key, familyEntries[family.key]);
                          _ensureFamilyOptions(family.key);
                          final options = _familyOptions[family.key];
                          final currentKey =
                              snapshot.providerFamilySelectedKeys[family.key] ??
                                  '';
                          final currentMode =
                              snapshot.providerFamilyModes[family.key] ??
                                  'oauth';
                          FamilyConnectionOption? connection;
                          for (final option
                              in options ?? const <FamilyConnectionOption>[]) {
                            if (option.key == currentKey ||
                                (option.mode == 'apiKey' &&
                                    currentMode == 'apiKey' &&
                                    currentKey.isEmpty)) {
                              connection = option;
                            }
                          }
                          final connectionSelect = Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 2),
                              decoration: BoxDecoration(
                                  border: Border.all(color: ink.border),
                                  borderRadius: BorderRadius.circular(10)),
                              child: options == null
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6),
                                      child: Text(
                                          uiText(context, '读取中…', 'Loading…'),
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: ink.subtlest)))
                                  : SizedBox(
                                      width: 190,
                                      child: DropdownButton<
                                          FamilyConnectionOption>(
                                      value: connection,
                                      underline: const SizedBox(),
                                      isDense: true,
                                      isExpanded: true,
                                      // Closed value = official short mode
                                      // label (`体验套餐`); menu rows keep
                                      // the badge so team projects stay
                                      // distinguishable inside the button
                                      // width.
                                      selectedItemBuilder: (context) => [
                                        for (final option in options)
                                          Text(
                                              _familyConnectionShortLabel(
                                                  option),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                      ],
                                      items: [
                                        for (final option in options)
                                          DropdownMenuItem(
                                              value: option,
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                        _familyConnectionShortLabel(
                                                            option),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis),
                                                    if (option.key.startsWith(
                                                        'team-plan:'))
                                                      Text(option.label,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                              fontSize: 11,
                                                              color: ink
                                                                  .subtlest)),
                                                  ]))
                                      ],
                                      onChanged: savingModes
                                          ? null
                                          : (option) async {
                                              if (option == null) return;
                                              await _applyFamilyConnection(
                                                  family.key, option);
                                            })));
                          final enabledPill = (active?.enabled ?? false)
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: ink.confirmationSurface,
                                      borderRadius:
                                          BorderRadius.circular(999)),
                                  child: Text(uiText(context, '已启用', 'Enabled'),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: ink.confirmationText)))
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: ink.hover,
                                      borderRadius: BorderRadius.circular(999)),
                                  child: Text(uiText(context, '已停用', 'Disabled'),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: ink.subtlest)));
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _settingsCard(ink, [
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Official header places the
                                            // select on the title row; narrow
                                            // panes move it below instead of
                                            // overflowing.
                                            LayoutBuilder(
                                                builder:
                                                    (context, constraints) {
                                              final connectionBlock = Row(
                                                  children: [
                                                    Text(
                                                        uiText(context,
                                                            '连接方式',
                                                            'Connection'),
                                                        style: TextStyle(
                                                            fontSize: 13,
                                                            color: ink
                                                                .subtlest)),
                                                    const SizedBox(width: 8),
                                                    connectionSelect,
                                                  ]);
                                              if (constraints.maxWidth <
                                                  560) {
                                                return Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(children: [
                                                        Expanded(
                                                            child: Text(
                                                                family.label,
                                                                style: const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500))),
                                                        const SizedBox(
                                                            width: 8),
                                                        enabledPill,
                                                      ]),
                                                      const SizedBox(
                                                          height: 10),
                                                      connectionBlock,
                                                    ]);
                                              }
                                              return Row(children: [
                                                Expanded(
                                                    child: Text(family.label,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w500))),
                                                const SizedBox(width: 8),
                                                enabledPill,
                                                const SizedBox(width: 12),
                                                connectionBlock,
                                              ]);
                                            }),
                                            if (options != null &&
                                                connection == null &&
                                                currentKey.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                  '${uiText(context, '当前连接方式', 'Current connection')}: $currentKey',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: ink.subtlest)),
                                            ],
                                            if (failedModes) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                  uiText(
                                                      context,
                                                      '保存失败，已保留原设置。',
                                                      'Save failed. The previous value is kept.'),
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          ink.diffRemoved)),
                                              TextButton(
                                                  onPressed: savingModes
                                                      ? null
                                                      : () => unawaited(controller.updatePatch((controller.lastAttempt('modelProviderFamilyModes|modelProviderFamilySelectedKeys')
                                                                  as Map?)
                                                              ?.cast<String,
                                                                  Object?>() ??
                                                          {
                                                            'modelProviderFamilyModes':
                                                                controller.lastAttempt(
                                                                    'modelProviderFamilyModes')
                                                          })),
                                                  child: Text(uiText(context,
                                                      '重试', 'Retry'))),
                                            ],
                                            if (active != null &&
                                                family.key != 'zapi')
                                              _providerPlanCard(ink, active),
                                          ])),
                                ]),
                                const SizedBox(height: 16),
                                Text(uiText(context, '模型列表', 'Models'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 8),
                                if (active == null)
                                  Text(
                                      uiText(context, '尚未同步，请先完成 OAuth 登录。',
                                          'Not synced yet. Complete OAuth login first.'),
                                      style: TextStyle(color: ink.subtlest))
                                else if (active.models.isEmpty)
                                  Text(
                                      uiText(context, '该供应商暂无模型。',
                                          'No models for this provider.'),
                                      style: TextStyle(color: ink.subtlest))
                                else
                                  _settingsCard(ink, [
                                    for (var index = 0;
                                        index < active.models.length;
                                        index++)
                                      _modelRow(context, ink, active, index),
                                  ]),
                              ]);
                        }

                        Widget rightPane;
                        if (selectedFamily != null) {
                          rightPane = familyDetailPane();
                        } else if (selected == null) {
                          final hasConnectionContent =
                              snapshot.providerFamilyModes.isNotEmpty ||
                                  failedModes ||
                                  _familyOptionsFailed.isNotEmpty;
                          rightPane = hasConnectionContent
                              ? _settingsCard(ink, [
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      child: connectionBlock()),
                                ])
                              : const SizedBox.shrink();
                        } else {
                          // Official custom-provider detail: header + actions
                          // + models; the connection mode lives on the family
                          // row only and never on custom rows.
                          final busy = _modelProviders!.isSaving(selected.id);
                          rightPane = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _settingsCard(ink, [
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              const LucideIcon('cpu', size: 18),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                  child: Text(selected.name,
                                                      style: const TextStyle(
                                                          fontWeight: FontWeight
                                                              .w500))),
                                              const SizedBox(width: 8),
                                              Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 2),
                                                  decoration: BoxDecoration(
                                                      color: selected.enabled
                                                          ? ink
                                                              .confirmationSurface
                                                          : ink.hover,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              999)),
                                                  child: Text(
                                                      selected.enabled
                                                          ? uiText(context,
                                                              '已启用', 'Enabled')
                                                          : uiText(
                                                              context,
                                                              '已停用',
                                                              'Disabled'),
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: selected.enabled
                                                              ? ink.confirmationText
                                                              : ink.subtlest))),
                                            ]),
                                            const SizedBox(height: 4),
                                            Wrap(
                                                alignment: WrapAlignment.end,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                spacing: 4,
                                                children: [
                                                  Text(uiText(
                                                      context,
                                                      '${selected.models.length} 模型 · ${selected.apiFormat}',
                                                      '${selected.models.length} models · ${selected.apiFormat}')),
                                                  IconButton(
                                                      tooltip: uiText(
                                                          context,
                                                          '编辑供应商',
                                                          'Edit provider'),
                                                      onPressed: busy
                                                          ? null
                                                          : () => unawaited(
                                                              _editProviderConfiguration(
                                                                  selected!)),
                                                      icon: const LucideIcon(
                                                          'pencil',
                                                          size: 16)),
                                                  if (_modelProviders!
                                                          .items.length >
                                                      1) ...[
                                                    IconButton(
                                                        tooltip: uiText(context,
                                                            '上移', 'Move up'),
                                                        onPressed: busy ||
                                                                _modelProviders!
                                                                        .items
                                                                        .first
                                                                        .id ==
                                                                    selected.id
                                                            ? null
                                                            : () => unawaited(
                                                                _reorderProvider(
                                                                    selected!,
                                                                    -1)),
                                                        icon: const LucideIcon(
                                                            'arrow-up',
                                                            size: 16)),
                                                    IconButton(
                                                        tooltip: uiText(context,
                                                            '下移', 'Move down'),
                                                        onPressed: busy ||
                                                                _modelProviders!
                                                                        .items
                                                                        .last
                                                                        .id ==
                                                                    selected.id
                                                            ? null
                                                            : () => unawaited(
                                                                _reorderProvider(
                                                                    selected!,
                                                                    1)),
                                                        icon: const LucideIcon(
                                                            'arrow-down',
                                                            size: 16)),
                                                  ],
                                                  if (_modelProviders!
                                                      .canDelete(selected))
                                                    IconButton(
                                                        tooltip: uiText(
                                                            context,
                                                            '删除供应商',
                                                            'Delete provider'),
                                                        onPressed: busy
                                                            ? null
                                                            : () => unawaited(
                                                                _deleteProvider(
                                                                    selected!)),
                                                        icon: const LucideIcon(
                                                            'trash-2',
                                                            size: 16)),
                                                ]),
                                            if (failedModes) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                  uiText(
                                                      context,
                                                      '保存失败，已保留原设置。',
                                                      'Save failed. The previous value is kept.'),
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: ink.diffRemoved)),
                                              TextButton(
                                                  onPressed: savingModes
                                                      ? null
                                                      : () => unawaited(controller
                                                          .updatePatch((controller
                                                                          .lastAttempt(
                                                                              'modelProviderFamilyModes|modelProviderFamilySelectedKeys')
                                                                      as Map?)
                                                                  ?.cast<String,
                                                                      Object?>() ??
                                                              {
                                                                'modelProviderFamilyModes':
                                                                    controller
                                                                        .lastAttempt(
                                                                            'modelProviderFamilyModes')
                                                              })),
                                                  child: Text(uiText(
                                                      context, '重试', 'Retry'))),
                                            ],
                                            if (_modelProviders!.errorOperation(
                                                        selected.id) ==
                                                    'delete' &&
                                                _modelProviders!.saveError(
                                                        selected.id) !=
                                                    null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                  uiText(
                                                      context,
                                                      '供应商删除失败：${_modelProviders!.saveError(selected.id)}',
                                                      'Provider delete failed: ${_modelProviders!.saveError(selected.id)}'),
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: ink.diffRemoved)),
                                            ],
                                          ])),
                                ]),
                                const SizedBox(height: 16),
                                Text(uiText(context, '模型列表', 'Models'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 8),
                                if (selected.models.isEmpty)
                                  Text(
                                      uiText(context, '该供应商暂无模型。',
                                          'No models for this provider.'),
                                      style: TextStyle(color: ink.subtlest))
                                else
                                  // Official 模型列表: each model row is its
                                  // own bordered box (no outer card).
                                  Column(
                                    children: [
                                      for (var index = 0;
                                          index < selected.models.length;
                                          index++)
                                        _modelRow(
                                            context, ink, selected, index),
                                  ]),
                                if (_modelProviderEditorGate(selected)
                                            .modelsEditMode !=
                                        'read-only' &&
                                    !_modelProviderEditorGate(selected)
                                        .modelsReadOnly)
                                  Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                          onPressed: _modelProviders!
                                                  .isSaving(selected.id)
                                              ? null
                                              : () => unawaited(
                                                  _editProviderModel(
                                                      selected!, null)),
                                          icon: const LucideIcon('plus',
                                              size: 16),
                                          label: Text(
                                              uiText(context, '添加模型', 'Add model')))),
                              ]);
                        }
                        return LayoutBuilder(builder: (context, constraints) {
                          final twoPane = constraints.maxWidth >= 720;
                          if (twoPane) {
                            // Official model page: ONE bordered container with
                            // an internal vertical divider between the
                            // provider list and the detail pane (not two
                            // sibling cards).
                            return Container(
                                decoration: BoxDecoration(
                                    border: Border.all(color: ink.border),
                                    borderRadius: BorderRadius.circular(12)),
                                clipBehavior: Clip.antiAlias,
                                child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                          width: 240, child: leftPaneContent),
                                      Expanded(
                                          child: Container(
                                              decoration: BoxDecoration(
                                                  border: Border(
                                                      left: BorderSide(
                                                          color:
                                                              ink.border))),
                                              padding: const EdgeInsets.all(16),
                                              child: rightPane)),
                                    ]));
                          }
                          final list = Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                  color: ink.surface,
                                  border: Border.all(color: ink.border),
                                  borderRadius: BorderRadius.circular(12)),
                              child: leftPaneContent);
                          return Column(children: [
                            list,
                            const SizedBox(height: 16),
                            rightPane,
                          ]);
                        });
                      }),
              ]);
            } else if (section == 'memory') {
              // Official memory page (1180 capture): one card with the
              // workspace-memory toggle, then a dashed note that the memory
              // details are desktop-only.
              children.add(_settingsCard(ink, [
                _remoteToggle(
                    context,
                    ink,
                    controller,
                    'memoryEnabled',
                    uiText(context, '工作区记忆', 'Workspace memory'),
                    snapshot.memoryEnabled,
                    description: uiText(
                        context,
                        '在工作区中保存并复用长期上下文，新会话生效。开启后可能增加模型调用和 Token 成本。',
                        'Save and reuse long-term workspace context for new '
                            'sessions. May increase model calls and token cost.'),
                    officialDefault: false),
              ]));
              children.add(const SizedBox(height: 16));
              children.add(SizedBox(
                  width: double.infinity,
                  child: _DashedNoteCard(
                      text: uiText(
                          context,
                          '记忆详情仅支持在本地桌面端查看，请前往本地桌面端的"记忆"设置。',
                          'Memory details are only available in the local '
                              'desktop app memory settings.'))));
            } else if (section == 'browser') {
              // Official remote browser page: the control card toggles the
              // browser-use official plugin (not a settingService key). The
              // data actions stay visible but disabled because the remote
              // host does not advertise the desktop-only file/data bridge.
              // The insecure-certificate switch is desktop-gated and remains
              // hidden for this remote page.
              children.add(_browserControlCard(context, ink, controller));
              children.add(const SizedBox(height: 16));
              children.add(Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(uiText(context, '浏览器数据', 'Browser data'),
                      style: TextStyle(fontSize: 13, color: ink.subtlest))));
              children.add(SizedBox(
                  width: double.infinity,
                  child: _settingsCard(ink, [
                    _browserDataAction(context, ink,
                        key: const ValueKey('browser-import-data'),
                        title:
                            uiText(context, '导入浏览器数据', 'Import browser data'),
                        description: uiText(context, '从桌面端浏览器导入 cookies 和本地存储。',
                            'Import cookies and local storage from a desktop browser.'),
                        action: uiText(context, '导入', 'Import')),
                    _browserDataAction(context, ink,
                        key: const ValueKey('browser-clear-cache'),
                        title: uiText(context, '清除缓存', 'Clear cache'),
                        description: uiText(context, '清除内置浏览器缓存数据。',
                            'Clear embedded browser cache data.'),
                        action: uiText(context, '清除', 'Clear')),
                    _browserDataAction(context, ink,
                        key: const ValueKey('browser-clear-all'),
                        title: uiText(context, '清除全部数据', 'Clear all data'),
                        description: uiText(context, '清除 cookies、本地存储和缓存。',
                            'Clear cookies, local storage and cache.'),
                        action: uiText(context, '清除全部', 'Clear all')),
                  ])));
              children.add(const SizedBox(height: 10));
              children.add(SizedBox(
                  width: double.infinity,
                  child: _DashedNoteCard(
                      text: uiText(context, '浏览器数据只能在 ZCode 桌面端管理。',
                          'Browser data can only be managed in the ZCode desktop app.'))));
            } else if (section == 'indexing') {
              // Official indexing page: 代码库 group label + one card with
              // the two official-labelled toggles; the snapshot toggle
              // writes both keys in one patch (user-configured flag).
              children.add(Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(uiText(context, '代码库', 'Codebase'),
                      style: TextStyle(fontSize: 13, color: ink.subtlest))));
              children.add(_settingsCard(ink, [
                _remoteTogglePatch(
                    context,
                    ink,
                    controller,
                    {
                      'repoSnapshotIndexingEnabled':
                          snapshot.repoSnapshotIndexingEnabled != true,
                      'repoSnapshotIndexingUserConfigured': true,
                    },
                    'repoSnapshotIndexingEnabled|repoSnapshotIndexingUserConfigured',
                    uiText(context, '索引新文件夹', 'Index new folders'),
                    snapshot.repoSnapshotIndexingEnabled,
                    description: uiText(
                        context,
                        '自动索引文件数少于 50,000 的新文件夹。',
                        'Automatically index new folders with fewer than '
                            '50,000 files.')),
                _remoteToggle(
                    context,
                    ink,
                    controller,
                    'instantGrepIndexingEnabled',
                    uiText(context, '索引存储库以实现即时搜索（测试版）',
                        'Index repositories for instant search (beta)'),
                    snapshot.instantGrepIndexingEnabled,
                    description: uiText(
                        context,
                        '自动对仓库进行索引，以加快 Grep 搜索速度。所有数据均存储在本地。',
                        'Indexes repositories to speed up Grep. All data '
                            'stays local.'),
                    officialDefault: false),
              ]));
            } else {
              children.addAll(_remoteSettingsPlaceholder(context, ink));
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children);
          })),
    ];
  }

  /// Official browser control card: the toggle drives the browser-use
  /// official plugin through the verified pluginManagement write; disabled
  /// while the catalog loads, while an operation is in flight, or when the
  /// plugin is not installed.
  Widget _browserControlCard(BuildContext context, InkTokens ink,
      RemoteSettingsController controller) {
    final catalog = _browserPlugins;
    const pluginId = 'browser-use@zcode-plugins-official';
    return ListenableBuilder(
        listenable: catalog ?? Listenable.merge(const []),
        builder: (context, _) {
          CatalogPlugin? item;
          if (catalog != null) {
            for (final candidate in catalog.items) {
              if (candidate.id == pluginId) {
                item = candidate;
                break;
              }
            }
          }
          final loading = catalog == null || catalog.loading;
          final saving = catalog?.operation != null;
          Widget trailing;
          if (loading) {
            trailing = _remoteSpinner();
          } else if (item == null || !item.installed) {
            trailing = _settingsSwitch(value: false, onChanged: null);
          } else {
            trailing = _settingsSwitch(
                key: const ValueKey('browser-control-toggle'),
                value: item.enabled,
                onChanged: saving
                    ? null
                    : (next) => unawaited(catalog.enable(item!, next)));
          }
          return _settingsCard(ink, [
            _settingsRow(
                ink,
                uiText(context, '开启内置浏览器控制', 'Built-in browser control'),
                uiText(
                    context,
                    '启用 Browser Use 官方插件，让新会话可以通过内置浏览器访问和操作网页。',
                    'Enables the official Browser Use plugin so new sessions '
                        'can open and operate pages in the embedded browser.'),
                trailing),
          ]);
        });
  }

  Widget _browserDataAction(
    BuildContext context,
    InkTokens ink, {
    required Key key,
    required String title,
    required String description,
    required String action,
  }) {
    final disabledReason = uiText(
        context, '仅支持在 ZCode 桌面端执行。', 'Available in the ZCode desktop app.');
    return _settingsRow(
      ink,
      title,
      description,
      Tooltip(
        message: disabledReason,
        child: OutlinedButton(
          key: key,
          onPressed: null,
          child: Text(action),
        ),
      ),
    );
  }

  /// E1.3: a written provider-family change invalidates every composer's
  /// prepared model options for the connected scope, so the next menu
  /// open refetches instead of showing stale candidates.
  SettingsNavigationResult _skillDraftNavigationResult(
      WorkspaceMonitor monitor) {
    return SettingsNavigationResult(
      target: TaskTarget(
        deviceId: monitor.source.deviceId,
        workspaceKey: monitor.source.workspaceKey,
        workspacePath: monitor.source.workspacePath ??
            (monitor.scope['workspacePath'] is String
                ? monitor.scope['workspacePath'] as String
                : null),
        sessionId: '',
        title: uiText(context, '新建任务', 'New task'),
      ),
    );
  }

  /// Prepares a plugin mention in the current workspace @draft and returns a
  /// typed target to the navigation caller. No task is sent here. The monitor
  /// captured by the initiating page owns the bridge and workspace identity;
  /// a later scope selection cannot redirect this draft to another workspace.
  Future<void> _preparePluginUseDraft(
      PluginUseDraft draft, WorkspaceMonitor sourceMonitor,
      [BuildContext? popContext]) async {
    final monitor = sourceMonitor;
    final currentMonitor = _pluginsWorkspaceMonitor ?? widget.remoteMonitor;
    if (currentMonitor != null &&
        !_samePluginMonitor(currentMonitor, monitor)) {
      // A callback from a retired page must never write into the newly
      // selected workspace or bridge.
      return;
    }
    final deviceId = monitor.source.deviceId;
    final workspaceKey = monitor.source.workspaceKey;
    final key = composerKey(deviceId, workspaceKey, null);
    final snapshot = widget.sessions.composers.inputSnapshots[key];
    final hasText = (widget.sessions.drafts[key] ?? '').trim().isNotEmpty ||
        (snapshot?.value.text ?? '').trim().isNotEmpty;
    final references = snapshot?.toJson()['references'];
    final hasReferences = references is List && references.isNotEmpty;
    final hasAttachments =
        widget.sessions.composers.attachmentDrafts[key]?.isNotEmpty == true;
    final navigatorContext = popContext ?? context;
    if (hasText || hasReferences || hasAttachments) {
      if (!mounted) return;
      await showDialog<void>(
        context: navigatorContext,
        builder: (dialogContext) => AlertDialog(
          title: Text(
              uiText(context, '当前草稿已有内容', 'Draft already contains content')),
          content: Text(uiText(context, '请先处理当前草稿、附件和引用，再准备插件草稿。当前内容已保留。',
              'Handle the current draft, attachments, and references before preparing a plugin draft. Your content was kept.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(uiText(context, '关闭', 'Close')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(navigatorContext)
                    .pop(_skillDraftNavigationResult(monitor));
              },
              child: Text(uiText(context, '返回 Composer', 'Back to Composer')),
            ),
          ],
        ),
      );
      return;
    }
    final composer = widget.sessions.composers.obtain(
      transport: monitor.bridge.conversation(monitor.scope),
      deviceId: deviceId,
      workspaceKey: workspaceKey,
    );
    final end = composer.input.text.length;
    composer.input.insertReference(
      TextRange(start: end, end: end),
      draft.reference,
    );
    final mention = draft.reference.markdown;
    final initial = draft.initialPrompt.trim();
    final extra = initial.startsWith(mention)
        ? initial.substring(mention.length).trim()
        : '';
    if (extra.isNotEmpty) composer.input.text += extra;
    if (mounted) {
      Navigator.of(navigatorContext).pop(_skillDraftNavigationResult(monitor));
    }
  }

  bool _samePluginMonitor(WorkspaceMonitor left, WorkspaceMonitor right) {
    if (!identical(left.bridge, right.bridge) ||
        left.source.deviceId != right.source.deviceId ||
        left.source.workspaceKey != right.source.workspaceKey) {
      return false;
    }
    String? path(WorkspaceMonitor value) {
      final candidate = value.scope['workspacePath'];
      return value.source.workspacePath ??
          (candidate is String ? candidate : null);
    }

    return path(left) == path(right);
  }

  Future<void> _prepareSkillCreatorDraft(SkillCreatorDraft draft,
      [WorkspaceMonitor? sourceMonitor]) async {
    final monitor = sourceMonitor ?? widget.remoteMonitor;
    if (monitor == null) return;
    final deviceId = monitor.source.deviceId;
    final workspaceKey = monitor.source.workspaceKey;
    final key = composerKey(deviceId, workspaceKey, null);
    final snapshot = widget.sessions.composers.inputSnapshots[key];
    final hasText = (widget.sessions.drafts[key] ?? '').trim().isNotEmpty ||
        (snapshot?.value.text ?? '').trim().isNotEmpty;
    final references = snapshot?.toJson()['references'];
    final hasReferences = references is List && references.isNotEmpty;
    final hasAttachments =
        widget.sessions.composers.attachmentDrafts[key]?.isNotEmpty == true;
    if (hasText || hasReferences || hasAttachments) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
              uiText(context, '当前草稿已有内容', 'Draft already contains content')),
          content: Text(uiText(context, '请先处理当前草稿、附件和引用，再准备新的技能草稿。当前内容已保留。',
              'Handle the current draft, attachments, and references before preparing a skill draft. Your content was kept.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(uiText(context, '关闭', 'Close')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop(_skillDraftNavigationResult(monitor));
              },
              child: Text(uiText(context, '返回 Composer', 'Back to Composer')),
            ),
          ],
        ),
      );
      return;
    }
    final composer = widget.sessions.composers.obtain(
      transport: monitor.bridge.conversation(monitor.scope),
      deviceId: deviceId,
      workspaceKey: workspaceKey,
    );
    composer.input.insertReference(
      TextRange(
          start: composer.input.text.length, end: composer.input.text.length),
      draft.reference,
    );
    if (mounted) {
      Navigator.of(context).pop(_skillDraftNavigationResult(monitor));
    }
  }

  void _invalidateComposerPrep({WorkspaceMonitor? scopeMonitor}) {
    // Model/provider writes normally use the page's current monitor. Callers
    // that edited a workspace-scoped catalog can pass its actual monitor so a
    // similarly named workspace on another device is never refreshed.
    final monitor = scopeMonitor ?? widget.remoteMonitor;
    if (monitor == null) return;
    unawaited(widget.sessions.refreshComposerScopeForMonitor(monitor));
  }

  /// Official 数据与统计 "引导" entry (`settings.onboarding`): opens the
  /// full multi-step onboarding wizard (welcome, category steps, migration
  /// and finish). It is a dialog action, not a section, so the page stays.
  Future<void> _openOnboardingDialog() async {
    final monitor = widget.remoteMonitor;
    if (monitor == null || !mounted) return;
    await OnboardingWizard.show(
      context,
      service: ChannelSettingsSyncService(monitor.bridge),
      workspacePath: monitor.source.workspacePath ??
          (monitor.scope['workspacePath'] is String
              ? monitor.scope['workspacePath'] as String
              : null),
      workspaceIdentity: monitor.scope['workspaceIdentity'] is String
          ? monitor.scope['workspaceIdentity'] as String
          : null,
    );
  }

  /// Dashed CTA row mirroring the official nav entry (rocket icon + 引导).
  Widget _onboardingNavItem(InkTokens ink) {
    return Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
        child: Material(
            color: Colors.transparent,
            child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => unawaited(_openOnboardingDialog()),
                child: CustomPaint(
                    foregroundPainter:
                        _DashedRoundedBorderPainter(color: ink.border),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: Row(children: [
                          LucideIcon('rocket', size: 16, color: ink.subtlest),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(uiText(context, '引导', 'Onboarding'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14))),
                        ]))))));
  }

  /// Official connection items for one family (`$Kt`/`oqt`): the API-key
  /// preset, the start-plan (体验套餐) and coding-plan (编程套餐) OAuth keys
  /// and one entry per subscribed team project. Team entries need
  /// authenticated pricing; a pricing failure only hides them. Labels mirror
  /// the official catalog (`EL.displayName` / `OL.providerName` + mode).
  List<FamilyConnectionOption> _familyConnectionOptions(
      String family, List<CodingPlanProduct> products) {
    final brand = switch (family) {
      'zai' => 'Z.ai',
      'bigmodel' => 'BigModel',
      _ => 'ZAPI',
    };
    final options = [
      FamilyConnectionOption(
          key: 'preset:builtin:$family',
          mode: 'apiKey',
          label: '$brand - API Key'),
    ];
    if (family == 'zai' || family == 'bigmodel') {
      options.add(FamilyConnectionOption(
          key: 'coding-plan:builtin:$family-start-plan',
          mode: 'oauth',
          label: uiText(context, '$brand - 体验套餐', '$brand - Start plan')));
      options.add(FamilyConnectionOption(
          key: 'coding-plan:builtin:$family-coding-plan',
          mode: 'oauth',
          label: uiText(context, '$brand - 编程套餐', '$brand - Coding plan')));
    }
    for (final product in products) {
      if (product.subscribed != true) continue;
      final projects = product.raw['teamProjects'];
      final usable = projects is List && projects.isNotEmpty
          ? projects.whereType<Map>()
          : <Map>[product.raw];
      for (final project in usable) {
        if (project['apiKeyStatus'] == 'unavailable') continue;
        final organization = project['organizationId'] is String
            ? (project['organizationId'] as String).trim()
            : '';
        final projectKey = project['projectId'] is String
            ? (project['projectId'] as String).trim()
            : '';
        if (organization.isEmpty || projectKey.isEmpty) continue;
        final key = 'team-plan:builtin:$family-coding-plan:'
            '${[
          product.id,
          organization,
          projectKey
        ].map(Uri.encodeComponent).join(':')}';
        options.add(FamilyConnectionOption(
            key: key,
            mode: 'oauth',
            label: '$brand - ${product.title} · $organization/$projectKey'));
      }
    }
    return options;
  }

  /// Official closed-select value (`connectionMode.*`): the short mode label,
  /// not the full option label — the ROG capture shows `体验套餐`.
  String _familyConnectionShortLabel(FamilyConnectionOption option) {
    if (option.mode == 'apiKey') {
      return uiText(context, 'API', 'API');
    }
    if (option.key.contains('-start-plan')) {
      return uiText(context, '体验套餐', 'Start plan');
    }
    if (option.key.startsWith('team-plan:')) {
      return uiText(context, '团队套餐', 'Team plan');
    }
    return uiText(context, '个人套餐', 'Coding plan');
  }

  /// Official `oqt`: the family's active provider is the selected-key's
  /// provider; an apiKey mode (or a missing key) resolves to the API-key
  /// preset provider (`builtin:<family>`).
  ModelProviderEntry? _familyActiveProviderEntry(RemoteSettingsSnapshot
      snapshot, String familyKey, List<ModelProviderEntry>? entries) {
    final list = entries ?? const <ModelProviderEntry>[];
    if (list.isEmpty) return null;
    final mode = snapshot.providerFamilyModes[familyKey] ?? 'oauth';
    final key = snapshot.providerFamilySelectedKeys[familyKey] ?? '';
    final preferred = mode == 'apiKey' || key.isEmpty
        ? 'builtin:$familyKey'
        : key.startsWith('coding-plan:')
            ? key.substring('coding-plan:'.length)
            : 'builtin:$familyKey-coding-plan';
    for (final entry in list) {
      if (entry.id == preferred) return entry;
    }
    return list.first;
  }

  void _ensureFamilyOptions(String family) {
    if (_familyOptions.containsKey(family)) return;
    final monitor = widget.remoteMonitor;
    final controller = _remoteSettings;
    if (monitor == null || controller == null) return;
    final generation = ++_familyOptionsGeneration;
    unawaited(() async {
      List<CodingPlanProduct> products = const [];
      var failed = false;
      try {
        final raw = await monitor.bridge.channels.call(
            Channels.codingPlanSubscription,
            'getEnterprisePricing',
            [
              {'authenticated': true, 'family': family}
            ],
            timeout: const Duration(seconds: 20));
        if (raw is Map && raw['productList'] is List) {
          products = (raw['productList'] as List)
              .whereType<Map>()
              .map(CodingPlanProduct.fromRaw)
              .toList();
        }
      } catch (_) {
        failed = true;
      }
      if (!mounted || generation != _familyOptionsGeneration) return;
      setState(() {
        _familyOptions[family] = _familyConnectionOptions(family, products);
        if (failed) _familyOptionsFailed.add(family);
      });
    }());
  }

  /// Official ModelProviderSection write: choosing a connection item writes
  /// the family mode and the selected key together (read-merge-write).
  Future<void> _applyFamilyConnection(
      String family, FamilyConnectionOption option) async {
    final controller = _remoteSettings;
    if (controller == null) return;
    await controller.updatePatch({
      'modelProviderFamilyModes':
          Map<String, String>.from(controller.snapshot.providerFamilyModes)
            ..[family] = option.mode,
      'modelProviderFamilySelectedKeys': Map<String, String>.from(
          controller.snapshot.providerFamilySelectedKeys)
        ..[family] = option.key,
    });
    if (controller.saveError(
            'modelProviderFamilyModes|modelProviderFamilySelectedKeys') ==
        null) {
      _invalidateComposerPrep();
    }
  }

  /// Shared toggle row for remote settings: spinner while saving, error +
  /// retry (last attempted value) on failure. Visible state only comes
  /// from the controller's post-write read-back. Rows render in the
  /// official card row shape (title + description left, control right).
  Widget _remoteToggle(
      BuildContext context,
      InkTokens ink,
      RemoteSettingsController controller,
      String key,
      String title,
      bool? value,
      {bool? officialDefault,
      String? description}) {
    final saving = controller.isSaving(key);
    final failed = controller.saveError(key) != null;
    Widget trailing;
    if (value == null && officialDefault == null) {
      trailing = Text('--', style: TextStyle(color: ink.subtlest));
    } else if (saving) {
      trailing = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      // A missing key falls back to the official component default
      // (`?? true` / `?? false` in the bundle); toggling it stores the
      // explicit value.
      trailing = _settingsSwitch(
          key: ValueKey('remote-toggle-$key'),
          value: value ?? officialDefault!,
          onChanged: controller.remoteOperationsAvailable
              ? (next) => unawaited(controller.update(key, next))
              : null);
    }
    return Column(children: [
      _settingsRow(ink, title, description, trailing),
      _saveFailedColumn(
          context,
          failed,
          saving,
          controller.remoteOperationsAvailable
              ? () => unawaited(controller.updatePatch(
                  (controller.lastAttempt(key) ?? const {})
                      as Map<String, Object?>))
              : null),
    ]);
  }

  /// Toggle variant for multi-key official patches (e.g. the indexing
  /// switch also stamps its user-configured flag in the same call).
  Widget _remoteTogglePatch(
      BuildContext context,
      InkTokens ink,
      RemoteSettingsController controller,
      Map<String, Object?> patch,
      String patchKey,
      String title,
      bool? value,
      {String? description}) {
    final saving = controller.isSaving(patchKey);
    final failed = controller.saveError(patchKey) != null;
    Widget trailing;
    if (value == null) {
      trailing = Text('--', style: TextStyle(color: ink.subtlest));
    } else if (saving) {
      trailing = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      trailing = _settingsSwitch(
          key: ValueKey('remote-toggle-$patchKey'),
          value: value,
          onChanged: controller.remoteOperationsAvailable
              ? (_) => unawaited(controller.updatePatch(patch))
              : null);
    }
    return Column(children: [
      _settingsRow(ink, title, description, trailing),
      _saveFailedColumn(
          context,
          failed,
          saving,
          controller.remoteOperationsAvailable
              ? () => unawaited(controller.updatePatch(
                  (controller.lastAttempt(patchKey) ?? const {})
                      as Map<String, Object?>))
              : null),
    ]);
  }

  /// Remote part of the General section. The official web client writes
  /// `taskAutoArchiveEnabled` via switch and `taskAutoArchiveOlderThanDays`
  /// via select with fixed 3/7/14/30-day options (IntlProvider bundle).
  Future<void> _loadSystemInfo(WorkspaceMonitor monitor) async {
    final generation = ++_systemInfoGeneration;
    String? platform;
    var shells = const <Map<String, Object?>>[];
    try {
      final info = await monitor.bridge.channels.call(
          Channels.system, 'info', const [],
          timeout: const Duration(seconds: 10));
      if (info is Map && info['platform'] is String) {
        platform = info['platform'] as String;
      }
    } catch (_) {}
    if (platform == 'win32') {
      try {
        final raw = await monitor.bridge.channels.call(
            Channels.system, 'listIntegratedTerminalShells', const [],
            timeout: const Duration(seconds: 10));
        if (raw is List) {
          shells = [
            for (final entry in raw)
              if (entry is Map && entry['id'] is String)
                {
                  'id': entry['id'] as String,
                  'label': entry['label'] is String
                      ? entry['label'] as String
                      : entry['id'] as String,
                  'dialect': entry['dialect'] is String
                      ? entry['dialect'] as String
                      : '',
                  'path':
                      entry['path'] is String ? entry['path'] as String : '',
                },
          ];
        }
      } catch (_) {}
    }
    if (!mounted || generation != _systemInfoGeneration) return;
    setState(() {
      _remotePlatform = platform;
      _terminalShells = shells;
    });
  }

  // Official vQt general page structure: bordered cards whose rows carry a
  // title + description on the left and the control on the right; text
  // inputs render as a full-width detail line with a save button.
  Widget _settingsCard(InkTokens ink, List<Widget> rows) => Container(
      decoration: BoxDecoration(
          color: ink.card,
          border: Border.all(color: ink.border),
          borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) const Divider(height: 1),
          row,
        ]
      ]));

  Widget _settingsRow(
          InkTokens ink, String title, String? description, Widget control) =>
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: LayoutBuilder(builder: (context, constraints) {
            final label =
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title),
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(description,
                    style: TextStyle(fontSize: 12.5, color: ink.subtlest)),
              ],
            ]);
            if (constraints.maxWidth < 420) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label,
                    const SizedBox(height: 8),
                    control,
                  ]);
            }
            return Row(children: [
              Expanded(child: label),
              const SizedBox(width: 12),
              control,
            ]);
          }));

  Widget _remoteSpinner() => const SizedBox(
      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));

  /// Keep the compact switch paint while retaining a 48px hit area.
  Widget _settingsSwitch({
    Key? key,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) =>
      SizedBox(
          width: 48,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: onChanged == null ? null : () => onChanged(!value),
                ),
              ),
              Transform.scale(
                scale: .62,
                child: Switch(
                  key: key,
                  value: value,
                  onChanged: onChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ));

  List<Widget> _generalContent(BuildContext context, InkTokens ink) {
    final prefs = widget.preferences;
    final remote = _remoteSettings;
    final languageLabel = switch (prefs.language) {
      'zh' => '中文简体',
      'en' => 'English',
      _ => uiText(context, '跟随系统', 'System'),
    };
    return [
      // Official yQt locale chip under the section title.
      Align(
          alignment: Alignment.centerLeft,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: ink.hover, borderRadius: BorderRadius.circular(8)),
              child:
                  Text(languageLabel, style: const TextStyle(fontSize: 12.5)))),
      const SizedBox(height: 16),
      _settingsCard(ink, [
        _settingsRow(
            ink,
            uiText(context, '界面语言', 'Interface language'),
            uiText(context, '选择应用 UI 的显示语言。',
                'Choose the display language of the app UI.'),
            SizedBox(
                width: 220,
                child: DropdownButton<String>(
                    value: prefs.language,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(
                          value: 'system',
                          child: Text(uiText(context, '跟随系统', 'System'))),
                      DropdownMenuItem(
                          value: 'zh',
                          child: Text(
                              uiText(context, '中文简体', 'Simplified Chinese'))),
                      DropdownMenuItem(
                          value: 'en',
                          child: Text(uiText(context, 'English', 'English')))
                    ],
                    onChanged: (value) {
                      if (value != null) unawaited(prefs.setLanguage(value));
                    }))),
      ]),
      if (remote == null) ...[
        const SizedBox(height: 16),
        Text(
            uiText(context, '未连接远端工作区，远端设置不可用。',
                'No remote workspace connected. Remote settings are unavailable.'),
            style: TextStyle(color: ink.subtlest)),
      ] else
        ListenableBuilder(
            listenable: remote,
            builder: (context, _) {
              final snapshot = remote.snapshot;

              // Official card layout: terminal group, proxy group, behavior
              // group and archive group. Rows are kept in separate lists so
              // an optional row (the win32-only shell select) never shifts
              // the group boundaries.
              final terminalRows = <Widget>[];
              final proxyRows = <Widget>[];
              final behaviorRows = <Widget>[];

              // Terminal card: profile inheritance, font override, the
              // win32-only integrated shell select and native search.
              terminalRows.add(_remoteToggle(
                  context,
                  ink,
                  remote,
                  'terminalInheritSystemProfile',
                  uiText(context, '继承系统终端 Profile',
                      'Inherit system terminal profile'),
                  snapshot.terminalInheritSystemProfile,
                  officialDefault: true,
                  description: uiText(
                      context,
                      '启动内置终端时尽量继承登录 shell 环境、代理、Kube 变量和本机终端字体。',
                      'When launching the built-in terminal, inherit login '
                          'shell environment, proxy, Kubernetes variables, '
                          'and local terminal font when possible.')));
              terminalRows.add(_RemoteTextSetting(
                  controller: remote,
                  settingKey: 'terminalFontFamily',
                  title: uiText(context, '终端字体', 'Terminal font'),
                  description: uiText(
                      context,
                      '留空时自动探测系统终端配置；填写后作为 ZCode 终端的字体覆盖。',
                      'Auto-detect when empty; otherwise overrides the ZCode terminal font.'),
                  placeholder: uiText(
                      context,
                      '留空自动继承，例如 MesloLGS NF, monospace',
                      'Empty to inherit, e.g. MesloLGS NF, monospace'),
                  monospace: true));
              if (_remotePlatform == 'win32') {
                terminalRows.add(_integratedShellRow(context, ink, remote));
              }
              terminalRows.add(_remoteToggle(
                  context,
                  ink,
                  remote,
                  'nativeSearchEnhancementsEnabled',
                  uiText(context, '增强 Find 和 Grep', 'Enhanced Find and Grep'),
                  snapshot.nativeSearchEnhancementsEnabled,
                  officialDefault: true,
                  description: uiText(
                      context,
                      '在新建会话或应用重启后恢复的会话中使用增强 Find 和 Grep。当前会话保持现有设置；Windows 的 Find 保持不变。',
                      'Use enhanced Find and Grep in new sessions and sessions '
                          'restored after an app restart. Active sessions keep '
                          'their current setting; Find remains unchanged on '
                          'Windows.')));

              // Proxy card: three independently saved text settings.
              Widget proxyText(String key, String title, String description,
                      String placeholder) =>
                  _RemoteTextSetting(
                      controller: remote,
                      settingKey: key,
                      title: title,
                      description: description,
                      placeholder: placeholder,
                      monospace: true);
              proxyRows.add(proxyText(
                  'httpProxy',
                  uiText(context, 'HTTP 代理', 'HTTP proxy'),
                  uiText(
                      context,
                      '模型、MCP、命令工具与应用渲染层的出口流量将经此代理，不读取系统环境变量。留空时这些流量直连，内置浏览器则跟随系统代理设置。修改后需重启应用生效。',
                      'Route model, MCP, command-tool, and app renderer egress '
                          'traffic through this proxy; system environment '
                          'variables are not read. Leave blank and that '
                          'traffic connects directly, while the embedded '
                          'browser follows your system proxy settings. Restart '
                          'the app to take effect.'),
                  uiText(
                      context,
                      '留空则内置浏览器跟随系统代理，例如 http://127.0.0.1:7890',
                      'Blank means the embedded browser follows the system '
                          'proxy, e.g. http://127.0.0.1:7890')));
              proxyRows.add(proxyText(
                  'httpProxyNoProxy',
                  uiText(context, '不使用代理的地址', 'No proxy'),
                  uiText(
                      context,
                      '匹配这些主机的请求将直连，不经过 HTTP 代理。多个规则用英文逗号分隔。修改后需重启应用生效。',
                      'Requests matching these hosts connect directly instead '
                          'of using the HTTP proxy. Separate rules with '
                          'commas. Restart the app to take effect.'),
                  uiText(
                      context,
                      '例如 localhost,127.0.0.1,::1,.example.com,*.corp.com',
                      'e.g. localhost,127.0.0.1,::1,.example.com,*.corp.com')));
              proxyRows.add(proxyText(
                  'httpProxyCaCertPath',
                  uiText(context, '自定义证书', 'Custom certificate'),
                  uiText(
                      context,
                      '可选。填写 PEM 根证书路径后，会作为 NODE_EXTRA_CA_CERTS 注入模型、MCP 与命令工具，并用于渲染层证书校验。修改后需重启应用生效。',
                      'Optional. Set a PEM root certificate path to inject it '
                          'as NODE_EXTRA_CA_CERTS for models, MCP, and command '
                          'tools, and to trust it in renderer certificate '
                          'verification. Restart the app to take effect.'),
                  uiText(context, '例如 /Users/name/certs/root-ca.pem',
                      'e.g. /Users/name/certs/root-ca.pem')));

              // Behavior card (official general page bottom group; the old
              // local “对话” section content lives here per official
              // structure).
              behaviorRows.add(_settingsRow(
                  ink,
                  uiText(context, '交互行为', 'Interaction behavior'),
                  uiText(
                      context,
                      '在 ZCode 运行时将后续操作加入队列，或引导至下一轮工具调用后运行。',
                      'While ZCode is running, add follow-up actions to the '
                          'queue or guide them to run after the next tool call.'),
                  remote.isSaving('zcodeInteractionBehavior')
                      ? _remoteSpinner()
                      : SizedBox(
                          width: 220,
                          child: DropdownButton<String>(
                              value: const {
                                'queue',
                                'guide'
                              }.contains(snapshot.zcodeInteractionBehavior)
                                  ? snapshot.zcodeInteractionBehavior
                                  : null,
                              isExpanded: true,
                              underline: const SizedBox(),
                              items: [
                                DropdownMenuItem(
                                    value: 'queue',
                                    child:
                                        Text(uiText(context, '队列', 'Queue'))),
                                DropdownMenuItem(
                                    value: 'guide',
                                    child:
                                        Text(uiText(context, '引导', 'Guide'))),
                              ],
                              onChanged: snapshot.zcodeInteractionBehavior ==
                                      null
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        unawaited(remote.update(
                                            'zcodeInteractionBehavior', value));
                                      }
                                    }))));
              behaviorRows.add(_remoteToggle(
                  context,
                  ink,
                  remote,
                  'askUserQuestionAutoResolutionEnabled',
                  uiText(context, '提问自动继续', 'Automatically continue questions'),
                  snapshot.askUserQuestionAutoResolutionEnabled,
                  officialDefault: true,
                  description: uiText(
                      context,
                      '开启后，Agent 提问 5 分钟未回答会自动继续；关闭后，当前和后续提问会一直等待你的回答。',
                      'When enabled, Agent questions automatically continue '
                          'after 5 minutes without an answer. When disabled, '
                          'current and future questions wait for your response.')));
              behaviorRows.add(_remoteToggle(
                  context,
                  ink,
                  remote,
                  'modelIoFullRetentionEnabled',
                  uiText(context, '完整保留模型 I/O', 'Keep complete model I/O'),
                  snapshot.modelIoFullRetentionEnabled,
                  officialDefault: false,
                  description: uiText(
                      context,
                      '保留完整的模型请求和响应，不自动压缩、限制大小或删除旧记录。',
                      'Keep complete model requests and responses without '
                          'compression, size limits, or automatic deletion.')));
              behaviorRows.add(_remoteToggle(
                  context,
                  ink,
                  remote,
                  'messageStreamShowReasoning',
                  uiText(context, '显示思考过程', 'Show reasoning'),
                  snapshot.messageStreamShowReasoning,
                  officialDefault: true,
                  description: uiText(
                      context,
                      '在消息流中展示完整的模型思考内容；关闭时每轮仍展示第一次思考。',
                      'Show full reasoning inside the message stream. When '
                          'off, the first reasoning item in each turn remains '
                          'visible.')));
              behaviorRows.add(_remoteToggle(
                  context,
                  ink,
                  remote,
                  'messageStreamShowTodos',
                  uiText(context, '显示待办', 'Show todos'),
                  snapshot.messageStreamShowTodos,
                  officialDefault: false,
                  description: uiText(context, '在消息流中展示 Todo 工具卡片。',
                      'Show Todo tool cards inside the message stream.')));
              behaviorRows.add(_remoteToggle(
                  context,
                  ink,
                  remote,
                  'toolGroupingExploreEnabled',
                  uiText(context, '分组探索工具', 'Group exploration tools'),
                  snapshot.toolGroupingExploreEnabled,
                  officialDefault: true,
                  description: uiText(
                      context,
                      '将连续的读取和搜索工具聚合为 Explore 分组。',
                      'Group consecutive reads and searches into an Explore '
                          'section.')));
              behaviorRows.add(_remoteToggle(
                  context,
                  ink,
                  remote,
                  'toolGroupingTerminalEnabled',
                  uiText(context, '分组终端命令', 'Group terminal commands'),
                  snapshot.toolGroupingTerminalEnabled,
                  officialDefault: true,
                  description: uiText(
                      context,
                      '将连续的非只读 Shell 命令聚合为 Terminal 分组。',
                      'Group consecutive non-read-only shell commands into a '
                          'Terminal section.')));
              behaviorRows.add(_remoteToggle(
                  context,
                  ink,
                  remote,
                  'toolGroupingChangesEnabled',
                  uiText(context, '分组文件更改', 'Group file changes'),
                  snapshot.toolGroupingChangesEnabled,
                  officialDefault: false,
                  description: uiText(
                      context,
                      '将连续的 Write、Edit 和 ApplyPatch 调用聚合为 Changes 分组。',
                      'Group consecutive Write, Edit, and ApplyPatch calls '
                          'into a Changes section.')));

              // Archive card (existing E1.2 write path).
              final days = snapshot.taskAutoArchiveOlderThanDays;
              final savingDays =
                  remote.isSaving('taskAutoArchiveOlderThanDays');
              const dayOptions = [3, 7, 14, 30];

              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    _settingsCard(ink, terminalRows),
                    const SizedBox(height: 16),
                    _settingsCard(ink, proxyRows),
                    const SizedBox(height: 16),
                    _settingsCard(ink, behaviorRows),
                    const SizedBox(height: 16),
                    _settingsCard(ink, [
                      _remoteToggle(
                          context,
                          ink,
                          remote,
                          'taskAutoArchiveEnabled',
                          uiText(context, '自动归档旧任务', 'Auto-archive old tasks'),
                          snapshot.taskAutoArchiveEnabled,
                          description: uiText(
                              context,
                              '定时扫描最近打开过的工作区，将已完成、无未读、未置顶且超过保留期的任务自动归档。',
                              'Periodically scan recently opened workspaces '
                                  'and automatically archive completed, '
                                  'unread-free, unpinned tasks after the '
                                  'retention window.')),
                      _settingsRow(
                          ink,
                          uiText(context, '归档保留时长', 'Archive retention'),
                          uiText(
                              context,
                              '任务最后更新时间早于该时长后，才会进入自动归档候选。',
                              'A task becomes eligible for auto-archive only '
                                  'after its last update is older than this '
                                  'window.'),
                          savingDays
                              ? _remoteSpinner()
                              : SizedBox(
                                  width: 220,
                                  child: DropdownButton<int>(
                                      value: days != null &&
                                              dayOptions.contains(days)
                                          ? days
                                          : null,
                                      isExpanded: true,
                                      underline: const SizedBox(),
                                      items: [
                                        for (final d in dayOptions)
                                          DropdownMenuItem(
                                              value: d,
                                              child: Text(uiText(
                                                  context,
                                                  '$d 天后归档',
                                                  'Archive after $d days')))
                                      ],
                                      onChanged: days == null ||
                                              !remote.remoteOperationsAvailable
                                          ? null
                                          : (value) {
                                              if (value != null) {
                                                unawaited(remote.update(
                                                    'taskAutoArchiveOlderThanDays',
                                                    value));
                                              }
                                            }))),
                    ]),
                    _saveFailedColumn(
                        context,
                        remote.saveError('taskAutoArchiveOlderThanDays') !=
                            null,
                        savingDays,
                        remote.remoteOperationsAvailable
                            ? () => unawaited(remote.update(
                                'taskAutoArchiveOlderThanDays',
                                remote.lastAttempt(
                                    'taskAutoArchiveOlderThanDays')))
                            : null),
                  ]);
            }),
    ];
  }

  Map<String, Object?>? _selectedShell(
      List<Map<String, Object?>> options, String id) {
    for (final shell in options) {
      if (shell['id'] == id) return shell;
    }
    return null;
  }

  Widget _integratedShellRow(
      BuildContext context, InkTokens ink, RemoteSettingsController remote) {
    final snapshot = remote.snapshot;
    final mode = snapshot.integratedTerminalShellMode;
    final selectedId = snapshot.integratedTerminalShellId;
    final saving = remote.isSaving('integratedTerminalShell');
    final options = <Map<String, Object?>>[
      // Official behavior: a stored shell that is not in the current system
      // list is still shown, built from the snapshot fields.
      if (mode == 'shell' &&
          selectedId != null &&
          !_terminalShells.any((shell) => shell['id'] == selectedId))
        {
          'id': selectedId,
          'label': snapshot.integratedTerminalShellLabel ?? selectedId,
          'dialect': snapshot.integratedTerminalShellDialect ?? '',
          'path': snapshot.integratedTerminalShellPath ?? '',
        },
      ..._terminalShells,
    ];
    return _settingsRow(
        ink,
        uiText(context, '集成终端Shell', 'Integrated terminal shell'),
        uiText(
            context,
            '仅新会话生效。Windows 下 Bash 工具用此 shell；自动优先 Git Bash，找不到回退 cmd.exe。',
            'Applies to new sessions only. Bash tools prefer the selected '
                'shell on Windows; auto prefers Git Bash and falls back to cmd.'),
        saving
            ? _remoteSpinner()
            : SizedBox(
                width: 220,
                child: DropdownButton<String>(
                    value: mode == 'shell' &&
                            selectedId != null &&
                            options.any((shell) => shell['id'] == selectedId)
                        ? selectedId
                        : (mode == 'shell' ? null : 'auto'),
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(
                          value: 'auto',
                          child: Text(uiText(context, '自动选择', 'Auto'))),
                      for (final shell in options)
                        DropdownMenuItem(
                            value: shell['id'] as String?,
                            child: Text((shell['label'] as String?) ??
                                (shell['id'] as String? ?? ''))),
                    ],
                    onChanged: remote.remoteOperationsAvailable
                        ? (id) {
                            if (id == null) return;
                            if (id == 'auto') {
                              unawaited(remote.update(
                                  'integratedTerminalShell', {'mode': 'auto'}));
                              return;
                            }
                            final shell = _selectedShell(options, id);
                            if (shell == null) return;
                            unawaited(remote.update('integratedTerminalShell', {
                              'mode': 'shell',
                              'dialect': shell['dialect'],
                              'id': shell['id'],
                              'label': shell['label'],
                              'path': shell['path'],
                            }));
                          }
                        : null)));
  }

  List<Widget> _mcpContent(BuildContext context, InkTokens ink) {
    final controller = _mcpCatalog;
    if (controller == null) {
      return _remoteSettingsPlaceholder(context, ink);
    }
    final currentMonitor = _mcpWorkspaceMonitor ?? widget.remoteMonitor;
    final workspaceOptions = buildSettingsScopeOptions(
      widget.sessions,
      current: currentMonitor,
    );
    SettingsScopeOption? selectedScope = _mcpWorkspaceScope;
    if (selectedScope == null && currentMonitor != null) {
      final currentIdentity =
          '${currentMonitor.source.deviceId}|${currentMonitor.source.workspaceKey}';
      for (final option in workspaceOptions) {
        if (option.identity == currentIdentity) {
          selectedScope = option;
          break;
        }
      }
    }
    return [
      McpSettingsPage(
        key: const ValueKey('settings-mcp-page'),
        catalog: controller,
        scope: _mcpScope,
        onScopeChanged: _selectMcpConfigScope,
        onOpenAuthorization: widget.onOpenExternal ?? _openMcpAuthorizationUrl,
        onImport: _openMcpImport,
        pluginCatalog: _mcpPlugins,
        workspaceScopeOptions: workspaceOptions,
        selectedWorkspaceScope: selectedScope,
        onWorkspaceScopeChanged: _selectMcpWorkspace,
      ),
    ];
  }

  List<Widget> _subagentsContent(BuildContext context, InkTokens ink) {
    final controller = _subagentsCatalog;
    if (controller == null) {
      return _remoteSettingsPlaceholder(context, ink);
    }
    final monitor = _subagentsWorkspaceMonitor ?? widget.remoteMonitor;
    return [
      SubagentsSettingsPage(
        catalog: controller,
        scopes: _subagentScopeOptions(),
        modelOptions: _subagentModelOptions(),
        onScopeSelected: _selectSubagentsWorkspace,
        onComposerRefresh: monitor == null
            ? null
            : () => _invalidateComposerPrep(scopeMonitor: monitor),
      ),
    ];
  }

  List<Widget> _commandsContent(BuildContext context, InkTokens ink) {
    final controller = _commandsCatalog;
    if (controller == null) {
      return _remoteSettingsPlaceholder(context, ink);
    }
    final monitor = _commandsWorkspaceMonitor ?? widget.remoteMonitor;
    return [
      CommandsSettingsPage(
        key: const ValueKey('settings-commands-page'),
        catalog: controller,
        scopes: _commandScopeOptions(),
        onScopeSelected: _selectCommandsWorkspace,
        onFormTargetSelected: _resolveCommandFormTarget,
        settingsSyncService:
            monitor == null ? null : ChannelSettingsSyncService(monitor.bridge),
        onComposerRefresh: monitor == null
            ? null
            : () => _invalidateComposerPrep(scopeMonitor: monitor),
      ),
    ];
  }

  /// Verified read-only `usageService.getEntitlementSnapshot` keyed to the
  /// selected provider (official VGt projection source). Generation guards
  /// late responses; a failure simply hides the plan card data.
  Future<void> _loadPlanEntitlement(ModelProviderEntry provider) async {
    final monitor = widget.remoteMonitor;
    if (monitor == null || _planEntitlementLoading) return;
    final generation = ++_planEntitlementGeneration;
    _planEntitlementLoading = true;
    try {
      final raw = await monitor.bridge
          .conversation(monitor.scope)
          .entitlementSnapshot(provider.id);
      final parsed = EntitlementSnapshot.parse(raw);
      if (!mounted || generation != _planEntitlementGeneration) return;
      setState(() {
        _planEntitlementFailed.remove(provider.id);
        _planEntitlement = parsed;
      });
    } catch (_) {
      if (!mounted || generation != _planEntitlementGeneration) return;
      setState(() {
        _planEntitlementFailed.add(provider.id);
        _planEntitlement = null;
      });
    } finally {
      _planEntitlementLoading = false;
    }
  }

  /// Official `EHt`: renew wins over expire; the date drops the year when it
  /// is the current one (`DHt`).
  String? _planDateLine(BuildContext context) {
    final snapshot = _planEntitlement;
    if (snapshot == null) return null;
    final renew = snapshot.renewTime;
    final expire = snapshot.expireTime;
    final int? millis;
    final String Function(DateTime) label;
    if (renew != null && renew > 0) {
      millis = renew;
      label = (d) => uiText(context, '续费', 'Renews');
    } else if (expire != null && expire > 0) {
      millis = expire;
      label = (d) => uiText(context, '到期', 'Expires');
    } else {
      return null;
    }
    final date = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    final sameYear = date.year == DateTime.now().year;
    final formatted = uiText(
        context,
        sameYear
            ? '${date.month}月${date.day}日'
            : '${date.year}年${date.month}月${date.day}日',
        sameYear
            ? '${date.month}/${date.day}'
            : '${date.month}/${date.day}/${date.year}');
    return '${label(date)} $formatted';
  }

  /// Official plan card quota tiles (5 hours / weekly / tool calls / ZCode
  /// MCP) mirroring the usage page selection; missing values render `--`.
  Widget _planQuotaTiles(BuildContext context, InkTokens ink) {
    final snapshot = _planEntitlement;
    if (snapshot == null) return const SizedBox.shrink();
    final tiles = <(String, QuotaLimit)>[
      if (snapshot.fiveHour case final QuotaLimit q)
        (uiText(context, '5h 用量', '5h usage'), q),
      if (snapshot.weekly case final QuotaLimit q)
        (uiText(context, '1w 用量', '1w usage'), q),
      if (snapshot.monthlyTool case final QuotaLimit q)
        (uiText(context, '工具调用', 'Tool calls'), q),
      if (snapshot.mcpAggregate case final QuotaLimit q) ('ZCode MCP', q),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (label, limit) in tiles)
            Container(
                width: 132,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    color: ink.surfaceFill,
                    borderRadius: BorderRadius.circular(8)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: ink.subtlest)),
                      const SizedBox(height: 4),
                      // Official `PF`: tiles show the REMAINING percent;
                      // the wire `percentage` is the used percent.
                      Text(formatQuotaPercent(limit.remainingPercent),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w500)),
                      if (limit.nextResetTime case final int reset
                          when reset > 0) ...[
                        const SizedBox(height: 2),
                        Text(() {
                          final date =
                              DateTime.fromMillisecondsSinceEpoch(reset)
                                  .toLocal();
                          return uiText(
                              context,
                              '${date.month}月${date.day}日',
                              '${date.month}/${date.day}');
                        }(),
                            style:
                                TextStyle(fontSize: 11, color: ink.subtlest)),
                      ],
                    ])),
        ]));
  }

  /// Official provider plan card (js-65 start-plan balance render + coding
  /// plan quota grid, ROG capture 2026-09-13): bordered card with the
  /// entitlement product name, expiry line, black upgrade pill, then the
  /// start-plan per-model 今日余额 rows or the coding-plan quota tiles
  /// (remaining percent). Read-only: data comes from the verified
  /// getEntitlementSnapshot; a failure simply hides the card.
  Widget _providerPlanCard(InkTokens ink, ModelProviderEntry provider) {
    if (_planEntitlement == null && !_planEntitlementLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadPlanEntitlement(provider));
      });
    }
    final snapshot = _planEntitlement;
    if (snapshot == null) {
      if (_planEntitlementFailed.contains(provider.id)) {
        return const SizedBox.shrink();
      }
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)));
    }
    String? subscribedTitle;
    for (final product in _upgradeCatalog?.products ?? const <CodingPlanProduct>[]) {
      if (product.subscribed == true) {
        subscribedTitle = product.title;
        break;
      }
    }
    final title = snapshot.planName ?? subscribedTitle;
    if (title == null &&
        snapshot.unavailableReason != null &&
        snapshot.limits.isEmpty &&
        !snapshot.hasSubscription) {
      // Official status line for a plan without data
      // (`codingPlan.status.notPurchased`).
      return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              uiText(context, '未开通，开通后启用。',
                  'Not purchased. Enable after subscribing.'),
              style: TextStyle(fontSize: 12, color: ink.subtlest)));
    }
    final expiryLine = _planExpiryLine(context);
    return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            border: Border.all(color: ink.border),
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(
                    title ?? uiText(context, '编程套餐', 'Coding plan'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600))),
            _upgradePill(ink),
            const SizedBox(width: 6),
            LucideIcon('info', size: 14, color: ink.subtlest),
          ]),
          if (expiryLine != null) ...[
            const SizedBox(height: 4),
            Text(expiryLine,
                style: TextStyle(fontSize: 13, color: ink.subtlest)),
          ],
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1)),
          if (snapshot.isStartPlan) ...[
            Text(uiText(context, '今日余额', "Today's balance"),
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            for (final limit in snapshot.startPlanLimits)
              _startPlanBalanceRow(context, ink, limit),
            if (snapshot.startPlanLimits.isEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(uiText(context, '暂无今日余额数据。', 'No balance data.'),
                      style: TextStyle(fontSize: 12, color: ink.subtlest))),
          ] else
            _planQuotaTiles(context, ink),
        ]));
  }

  /// Official black upgrade pill (rocket + 升级 + outlined 150% 配额 badge,
  /// `billingDiscountInfo`); opens the existing pricing/upgrade page.
  Widget _upgradePill(InkTokens ink) {
    return InkWell(
        onTap: _upgradeCatalog == null
            ? null
            : () {
                Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            UpgradePage(catalog: _upgradeCatalog!)));
              },
        child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const LucideIcon('rocket', size: 12, color: Colors.white),
              const SizedBox(width: 4),
              Text(uiText(context, '升级', 'Upgrade'),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white)),
              const SizedBox(width: 6),
              Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.white70),
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(uiText(context, '150% 配额', '150% quota'),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white))),
            ])));
  }

  /// Official start-plan balance row (`gZe`): model label, remaining percent
  /// (`bI`/`xI` semantics), reset date, progress bar and the grouped
  /// remaining/total token line.
  Widget _startPlanBalanceRow(
      BuildContext context, InkTokens ink, QuotaLimit limit) {
    final remaining = limit.remaining;
    final total = limit.number ?? limit.unit;
    final percent = startPlanRemainingPercent(remaining, total);
    return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: ink.surfaceFill,
            border: Border.all(color: ink.border),
            borderRadius: BorderRadius.circular(12)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(startPlanLimitLabel(limit),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatStartPlanPercent(remaining, total),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (limit.nextResetTime case final int reset when reset > 0)
              Text(
                  uiText(
                      context,
                      () {
                        final date = DateTime.fromMillisecondsSinceEpoch(
                                reset)
                            .toLocal();
                        return '${date.month}月${date.day}日';
                      }(),
                      () {
                        final date = DateTime.fromMillisecondsSinceEpoch(
                                reset)
                            .toLocal();
                        return '${date.month}/${date.day}';
                      }()),
                  style: TextStyle(fontSize: 12, color: ink.subtlest)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                  height: 5,
                  child: LinearProgressIndicator(
                      value: percent == null ? 0 : percent / 100,
                      minHeight: 5,
                      backgroundColor: ink.hover,
                      valueColor:
                          AlwaysStoppedAnimation(ink.diffAdded)))),
          const SizedBox(height: 8),
          Text('${formatTokenCount(remaining)} / ${formatTokenCount(total)}',
              style: TextStyle(fontSize: 12, color: ink.subtlest)),
        ]));
  }

  /// Official start-plan expiry uses date + time (`过期时间 9月14日 09:00`,
  /// `startPlan.expiresAt`); coding plans keep the renew-over-expire rule
  /// from `EHt`.
  String? _planExpiryLine(BuildContext context) {
    final snapshot = _planEntitlement;
    if (snapshot == null) return null;
    if (snapshot.isStartPlan) {
      final expire = snapshot.expireTime;
      if (expire == null || expire <= 0) return null;
      final date = DateTime.fromMillisecondsSinceEpoch(expire).toLocal();
      final clock =
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      return uiText(context, '过期时间 ${date.month}月${date.day}日 $clock',
          'Expires ${date.month}/${date.day} $clock');
    }
    return _planDateLine(context);
  }

  List<Widget> _pluginsContent(BuildContext context, InkTokens ink) {
    final monitor = _pluginsWorkspaceMonitor ?? widget.remoteMonitor;
    final catalog = _pluginsCatalog;
    if (monitor == null || catalog == null) {
      return _remoteSettingsPlaceholder(context, ink);
    }
    final workspaceOptions = _pluginsScopeOptions();
    SettingsScopeOption? selectedScope = _pluginsWorkspaceScope;
    if (selectedScope == null) {
      final currentIdentity =
          '${monitor.source.deviceId}|${monitor.source.workspaceKey}';
      selectedScope = workspaceOptions
          .where((option) => option.identity == currentIdentity)
          .firstOrNull;
    }
    return [
      PluginsSettingsPage(
        key: const ValueKey('settings-plugins-page'),
        catalog: catalog,
        embedded: true,
        scope: _pluginsScope,
        onScopeChanged: _selectPluginConfigScope,
        workspaceScopeOptions: workspaceOptions,
        selectedWorkspaceScope: selectedScope,
        onWorkspaceScopeChanged: _selectPluginsWorkspace,
        onOpenMarketplace: _openPluginManager,
        onUsePrompt: (draft) => _preparePluginUseDraft(draft, monitor),
      ),
    ];
  }

  List<Widget> _skillsContent(BuildContext context, InkTokens ink) {
    final controller = _skillsCatalog;
    if (controller == null) {
      return _remoteSettingsPlaceholder(context, ink);
    }
    final monitor = _skillsWorkspaceMonitor ?? widget.remoteMonitor;
    final workspaceOptions = buildSettingsScopeOptions(
      widget.sessions,
      current: monitor,
    );
    SettingsScopeOption? selectedScope = _skillsWorkspaceScope;
    if (selectedScope == null && monitor != null) {
      final currentIdentity =
          '${monitor.source.deviceId}|${monitor.source.workspaceKey}';
      selectedScope = workspaceOptions
          .where((option) => option.identity == currentIdentity)
          .firstOrNull;
    }
    return [
      SkillsSettingsPage(
        key: const ValueKey('settings-skills-page'),
        catalog: controller,
        // This catalog is refreshed from the exact selected monitor and
        // carries the authoritative installed/enabled plugin projection.
        pluginCatalog: _skillsPlugins,
        scope: _skillsScope,
        onScopeChanged: _selectSkillsConfigScope,
        settingsSyncService:
            monitor == null ? null : ChannelSettingsSyncService(monitor.bridge),
        workspaceScopeOptions: workspaceOptions,
        selectedWorkspaceScope: selectedScope,
        onWorkspaceScopeChanged: _selectSkillsWorkspace,
        onCreateTask: monitor == null
            ? null
            : (draft) => _prepareSkillCreatorDraft(draft, monitor),
        onComposerRefresh: monitor == null
            ? null
            : () => widget.sessions.refreshComposerScopeForMonitor(monitor),
      ),
    ];
  }

  List<Widget> _remoteSettingsPlaceholder(BuildContext context, InkTokens ink) {
    return [
      Text(
          uiText(context, '远控设置需要连接远端桌面后加载。',
              'Remote settings require a connected remote desktop.'),
          style: TextStyle(color: ink.subtlest)),
      const SizedBox(height: 8),
      Text(
          uiText(context, '此节在连接可用时将显示当前值、保存和失败重试。',
              'This section will show current values, save and retry when connected.'),
          style: TextStyle(color: ink.subtlest, fontSize: 12)),
    ];
  }

  Widget _row(String title, Widget trailing, {String? description}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(builder: (context, constraints) {
        final ink = ZInk.of(Theme.of(context).colorScheme);
        final label =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description,
                style: TextStyle(fontSize: 12.5, color: ink.subtlest)),
          ],
        ]);
        if (constraints.maxWidth < 420) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: 8),
                trailing,
              ]);
        }
        return Row(children: [
          Expanded(child: label),
          const SizedBox(width: 16),
          Flexible(
              child: Align(alignment: Alignment.centerRight, child: trailing))
        ]);
      }));
}

class _ProviderCreateDialog extends StatefulWidget {
  const _ProviderCreateDialog({required this.catalog});

  final ModelProvidersCatalog catalog;

  @override
  State<_ProviderCreateDialog> createState() => _ProviderCreateDialogState();
}

class _ProviderCreateDialogState extends State<_ProviderCreateDialog> {
  final _name = TextEditingController();
  final _baseURL = TextEditingController();
  final _apiKey = TextEditingController();
  final _modelName = TextEditingController();
  final _contextWindow = TextEditingController(text: '128000');
  String _apiFormat = 'anthropic-messages';
  bool _submitting = false;
  Object? _error;

  @override
  void dispose() {
    _name.dispose();
    _baseURL.dispose();
    _apiKey.dispose();
    _modelName.dispose();
    _contextWindow.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _baseURL.text.trim().isNotEmpty &&
      _modelName.text.trim().isNotEmpty &&
      (int.tryParse(_contextWindow.text.trim()) ?? 0) > 0;

  Future<void> _submit() async {
    if (_submitting || !_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final created = await widget.catalog.createCustomProvider(
      name: _name.text,
      baseURL: _baseURL.text,
      apiKey: _apiKey.text,
      apiFormat: _apiFormat,
      modelName: _modelName.text,
      contextWindow: int.tryParse(_contextWindow.text.trim()) ?? 0,
    );
    if (!mounted) return;
    if (created) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = widget.catalog.creationError;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(uiText(context, '添加模型供应商', 'Add model provider')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: uiText(context, '名称', 'Name'),
                hintText: uiText(context, '新供应商', 'New provider'),
              ),
            ),
            TextField(
              controller: _baseURL,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: uiText(context, 'Base URL', 'Base URL'),
                hintText: 'https://api.example.com/v1',
              ),
            ),
            TextField(
              controller: _apiKey,
              onChanged: (_) => setState(() {}),
              obscureText: true,
              decoration: InputDecoration(
                labelText: uiText(context, 'API Key', 'API Key'),
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _apiFormat,
              decoration: InputDecoration(
                labelText: uiText(context, 'API 格式', 'API format'),
              ),
              items: [
                for (final format in const [
                  'anthropic-messages',
                  'openai-chat-completions',
                  'openai-responses',
                ])
                  DropdownMenuItem(value: format, child: Text(format)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _apiFormat = value);
              },
            ),
            TextField(
              controller: _modelName,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: uiText(context, '初始模型', 'Initial model'),
              ),
            ),
            TextField(
              controller: _contextWindow,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: uiText(context, '上下文窗口', 'Context window'),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  uiText(context, '保存失败：$_error', 'Save failed: $_error'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: Text(uiText(context, '取消', 'Cancel')),
        ),
        ListenableBuilder(
          listenable: widget.catalog,
          builder: (context, _) {
            final busy = _submitting || widget.catalog.isCreatingProvider;
            return FilledButton(
              onPressed: busy || !_canSubmit ? null : _submit,
              child: Text(uiText(context, '添加供应商', 'Add provider')),
            );
          },
        ),
      ],
    );
  }
}

class _ModelProviderEditorGate {
  const _ModelProviderEditorGate({
    required this.readOnlyEndpoints,
    required this.readOnlyApiKey,
    required this.nameEditable,
    required this.modelsReadOnly,
    required this.hideConnectionSection,
    required this.hideApiKeySection,
    required this.modelsEditMode,
  });

  final bool readOnlyEndpoints;
  final bool readOnlyApiKey;
  final bool nameEditable;
  final bool modelsReadOnly;
  final bool hideConnectionSection;
  final bool hideApiKeySection;
  final String? modelsEditMode;
}

/// One selectable connection entry of a provider family (official
/// ModelProviderSection item): the key written into
/// `modelProviderFamilySelectedKeys` and the family mode it implies.
class FamilyConnectionOption {
  const FamilyConnectionOption({
    required this.key,
    required this.mode,
    required this.label,
  });

  final String key;
  final String mode;
  final String label;
}

/// Official general-page text setting: title + description with a save
/// button on the title line and a full-width monospace input below. The
/// button enables only when the trimmed input differs from the remote
/// snapshot; a failed save keeps the user text for retry.
class _RemoteTextSetting extends StatefulWidget {
  const _RemoteTextSetting({
    required this.controller,
    required this.settingKey,
    required this.title,
    this.description,
    this.placeholder,
    this.monospace = false,
  });

  final RemoteSettingsController controller;
  final String settingKey;
  final String title;
  final String? description;
  final String? placeholder;
  final bool monospace;

  @override
  State<_RemoteTextSetting> createState() => _RemoteTextSettingState();
}

class _RemoteTextSettingState extends State<_RemoteTextSetting> {
  final TextEditingController _text = TextEditingController();
  String? _lastSynced;

  @override
  void initState() {
    super.initState();
    _syncFromSnapshot();
    widget.controller.addListener(_onRemoteChanged);
  }

  @override
  void didUpdateWidget(covariant _RemoteTextSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onRemoteChanged);
      widget.controller.addListener(_onRemoteChanged);
      _lastSynced = null;
      _syncFromSnapshot();
    }
  }

  String _snapshotText() {
    final value = widget.controller.snapshot.values[widget.settingKey];
    if (value == null) return '';
    return value is String ? value : '$value';
  }

  // A pending user edit (text differs from the last synced snapshot) is
  // never overwritten by a refresh; the official page re-syncs
  // unconditionally, but that would erase typing mid-save.
  void _syncFromSnapshot() {
    final current = _snapshotText();
    if (_lastSynced == current) return;
    final dirty = _lastSynced != null && _text.text.trim() != _lastSynced;
    _lastSynced = current;
    if (!dirty && _text.text != current) {
      _text.text = current;
    }
  }

  void _onRemoteChanged() {
    if (!mounted) return;
    setState(_syncFromSnapshot);
  }

  bool get _dirty => _text.text.trim() != _lastSynced;

  Future<void> _save() async {
    if (!_dirty) return;
    await widget.controller.update(widget.settingKey, _text.text.trim());
    // Official behavior: after a successful save the input shows the stored
    // (trimmed) value. A failed save keeps the user text for retry.
    if (!mounted) return;
    if (widget.controller.saveError(widget.settingKey) == null) {
      final stored = _snapshotText();
      _text.text = stored;
      _lastSynced = stored;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onRemoteChanged);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saving = widget.controller.isSaving(widget.settingKey);
    final failed = widget.controller.saveError(widget.settingKey) != null;
    final saveButton = OutlinedButton(
        onPressed:
            _dirty && !saving && widget.controller.remoteOperationsAvailable
                ? () => unawaited(_save())
                : null,
        child: Text(
            saving
                ? uiText(context, '保存中…', 'Saving…')
                : uiText(context, '保存', 'Save'),
            style: const TextStyle(fontSize: 13)));
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (context, constraints) {
            final label =
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title),
              if (widget.description != null) ...[
                const SizedBox(height: 4),
                Text(widget.description!,
                    style: TextStyle(
                        fontSize: 12.5,
                        color:
                            ZInk.of(Theme.of(context).colorScheme).subtlest)),
              ],
            ]);
            if (constraints.maxWidth < 420) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [label, const SizedBox(height: 8), saveButton]);
            }
            return Row(children: [
              Expanded(child: label),
              const SizedBox(width: 12),
              saveButton,
            ]);
          }),
          const SizedBox(height: 8),
          TextField(
              controller: _text,
              enabled: widget.controller.remoteOperationsAvailable,
              onSubmitted: (_) => widget.controller.remoteOperationsAvailable
                  ? unawaited(_save())
                  : null,
              style: widget.monospace
                  ? const TextStyle(fontFamily: 'monospace', fontSize: 13)
                  : null,
              decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.placeholder,
                  border: const OutlineInputBorder())),
          _saveFailedColumn(
              context,
              failed,
              saving,
              widget.controller.remoteOperationsAvailable
                  ? () => unawaited(widget.controller.update(
                      widget.settingKey,
                      (widget.controller.lastAttempt(widget.settingKey)
                              as Map<String, Object?>?)?[widget.settingKey] ??
                          _text.text.trim()))
                  : null),
        ]));
  }
}

Widget _saveFailedColumn(
    BuildContext context, bool failed, bool saving, VoidCallback? onRetry) {
  if (!failed) return const SizedBox.shrink();
  return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Text(
            uiText(context, '保存失败，已保留原设置。',
                'Save failed. The previous value is kept.'),
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(width: 12),
        OutlinedButton(
            onPressed: saving ? null : onRetry,
            child: Text(uiText(context, '重试', 'Retry'))),
      ]));
}

/// Official dashed empty-state note card (memory details / hooks empty
/// states): centred subtle text inside a dashed rounded border.
class _DashedNoteCard extends StatelessWidget {
  const _DashedNoteCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return CustomPaint(
        painter: _DashedRoundedBorderPainter(color: ink.border),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 30),
            child: Center(
                child: Text(text,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ink.subtlest)))));
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  _DashedRoundedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const radius = 12.0;
    const dash = 5.0;
    const gap = 4.0;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var drawn = 0.0;
      while (drawn < metric.length) {
        final end = drawn + dash > metric.length ? metric.length : drawn + dash;
        canvas.drawPath(metric.extractPath(drawn, end), paint);
        drawn += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Official preset families (js-1 `EL`/`x5`/`bo`): zhipu-family provider ids
/// collapse into brand rows. `zhipuFamilyOf` mirrors the official id check
/// (`fVt`/`isBuiltinProviderId`), which is id-based, not source-based.
class ZhipuFamily {
  const ZhipuFamily(this.key, this.label);

  final String key;

  /// Official nav/detail brand name (`OL.providerName`; ZAPI has none on the
  /// wire, the row only appears when the intranet preset synced).
  final String label;
}

const List<ZhipuFamily> kZhipuFamilies = [
  ZhipuFamily('bigmodel', 'BigModel'),
  ZhipuFamily('zai', 'Z.ai'),
  ZhipuFamily('zapi', 'ZAPI'),
];

ZhipuFamily? zhipuFamilyOfId(String? id) {
  if (id == null) return null;
  if (id == 'builtin:zapi') return kZhipuFamilies[2];
  if (id.startsWith('builtin:zai')) return kZhipuFamilies[1];
  if (id.startsWith('builtin:bigmodel')) return kZhipuFamilies[0];
  return null;
}

/// Official number grouping for start-plan balance rows
/// (`126,741,605 / 300,000,000` — Intl en-US grouping in the bundle card).
String formatTokenCount(Object? value) {
  final num? parsed = value is num
      ? value
      : (value is String ? num.tryParse(value.trim()) : null);
  if (parsed == null || !parsed.isFinite) return '--';
  final digits = parsed.round().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    final remaining = digits.length - index;
    buffer.writeCharCode(digits.codeUnitAt(index));
    if (remaining > 1 && (remaining - 1) % 3 == 0) buffer.write(',');
  }
  return buffer.toString();
}
