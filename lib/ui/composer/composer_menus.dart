import 'package:flutter/material.dart';

import '../../protocol/conversation.dart';
import '../../state/client_preferences.dart';
import '../../state/composer_config.dart';
import '../../state/composer_controller.dart';
import '../../state/composer_model_projection.dart';
import '../../state/model_provider_catalog.dart';
import '../official_icons.dart';
import '../theme.dart';
import 'composer_mode_metadata.dart';
import 'composer_popover.dart';
import '../mobile/option_sheet.dart';

Future<String?> showComposerModeMenu(
    BuildContext anchor, ComposerController controller) {
  return showComposerPopover<String>(
    anchor,
    width: 256,
    gap: 4,
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _ModeMenu(controller: controller),
    ),
  );
}

Future<String?> showComposerModelMenu(
    BuildContext anchor, ComposerController controller,
    {VoidCallback? onManageModels}) {
  return showComposerPopover<String>(
    anchor,
    // Official w-48 picker with 16px viewport collision padding.
    width: 192,
    maxHeight: 288,
    collisionPadding: 16,
    gap: 4,
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _ModelMenu(
        controller: controller,
        onManageModels: onManageModels,
      ),
    ),
  );
}

/// Compact-shell bottom sheet for the collaboration mode. Shares the same
/// controller and select callback as the anchored popover; only the shell
/// differs.
Future<String?> showComposerModeSheet(
    BuildContext context, ComposerController controller) {
  return showMobileOptionSheet<String>(context: context, title: uiText(
      context, '协作模式', 'Collaboration mode'), optionsBuilder: (sheetContext) {
    final options = controller.options.modes;
    final selected = controller.config['mode'] as String?;
    final enabled = controller.canConfigureMode;
    final family = familyForModeValues([for (final o in options) o.value]);
    final provider = controller.config['provider'] as String?;
    return [
      for (final option in options)
        MobileSheetOption<String>(
          value: option.value,
          label: modeLabel(sheetContext, option.value, option.name, provider,
              family),
          subtitle:
              modeDescription(sheetContext, option, provider, family),
          icon: modeIconForValue(option.value),
          selected: option.value == selected,
          enabled: enabled,
        )
    ];
  });
}

/// Compact-shell bottom sheet for model selection. The metadata projection
/// comes from the same [ModelProvidersCatalog] flow as the anchored menu
/// ([_ModelMenuData]), so there is no second business state. Picking the
/// sentinel value [composerManageModelsSentinel] means "open manage page".
Future<String?> showComposerModelSheet(
    BuildContext context, ComposerController controller,
    {VoidCallback? onManageModels}) {
  return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ModelMenuData(
            controller: controller,
            builder: (innerContext, projection, metadataError,
                    metadataLoading, refresh) =>
                MobileOptionSheet<String>(
                    title: uiText(context, '选择模型', 'Select model'),
                    searchable: true,
                    searchHint: uiText(context, '搜索模型', 'Search models'),
                    optionsBuilder: (rowsContext) => _modelSheetRows(
                        rowsContext,
                        controller,
                        projection,
                        metadataError,
                        metadataLoading,
                        onManageModels)),
          ));
}

const String composerManageModelsSentinel = '::manage';

List<MobileSheetOption<String>> _modelSheetRows(
    BuildContext context,
    ComposerController controller,
    ComposerModelCatalogProjection? projection,
    Object? metadataError,
    bool metadataLoading,
    VoidCallback? onManageModels) {
  final selected = controller.options.model(controller.config)?.value;
  final enabled = controller.canConfigureModel;
  final rows = <MobileSheetOption<String>>[];
  for (final group in controller.options.modelGroupsFor(projection)) {
    if (!group.directItems) {
      rows.add(MobileSheetOption<String>(
          value: 'header:${group.id}',
          label: group.badgeLabel?.trim().isNotEmpty == true
              ? '${group.label} · ${group.badgeLabel}'
              : group.label,
          sectionHeader: true));
    }
    for (final item in group.items) {
      rows.add(MobileSheetOption<String>(
        value: item.value,
        label: item.name,
        subtitle: group.directItems ? null : group.label,
        selected: item.value == selected,
        enabled: enabled,
        trailingIcon: group.visionModelValues.contains(item.value)
            ? 'file-image'
            : null,
      ));
    }
  }
  if (metadataError != null) {
    rows.add(MobileSheetOption<String>(
        value: 'header:retry',
        label: metadataLoading
            ? uiText(context, '模型信息加载中', 'Loading model metadata')
            : uiText(context, '重试模型信息', 'Retry model metadata'),
        sectionHeader: true));
  }
  if (onManageModels != null) {
    rows.add(MobileSheetOption<String>(
        value: '::manage',
        label: uiText(context, '管理模型', 'Manage models'),
        enabled: true));
  }
  return rows;
}

/// Shared async metadata source for the anchored model menu and the mobile
/// model sheet: one owner for the catalog lifecycle and refresh state.
class _ModelMenuData extends StatefulWidget {
  const _ModelMenuData({required this.controller, required this.builder});
  final ComposerController controller;
  final Widget Function(
          BuildContext context,
          ComposerModelCatalogProjection? projection,
          Object? metadataError,
          bool metadataLoading,
          VoidCallback refresh)
      builder;
  @override
  State<_ModelMenuData> createState() => _ModelMenuDataState();
}

class _ModelMenuDataState extends State<_ModelMenuData> {
  ModelProvidersCatalog? _catalog;
  ComposerModelCatalogProjection? _projection;
  Object? _metadataError;
  int _generation = 0;
  bool _metadataLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshMetadata();
  }

  Future<void> _refreshMetadata() async {
    if (_metadataLoading || !mounted) return;
    _metadataLoading = true;
    final generation = ++_generation;
    _catalog?.dispose();
    final catalog = ModelProvidersCatalog(
      session: widget.controller.transport.session,
      scopeKey: widget.controller.key,
    );
    _catalog = catalog;
    if (mounted) setState(() {});
    Map<String, dynamic> familySelection = const {};
    Object? familyError;
    try {
      final familyFuture =
          widget.controller.transport.providerFamilySelection();
      final catalogFuture = catalog.refresh();
      try {
        familySelection = await familyFuture;
      } catch (error) {
        familyError = error;
      }
      await catalogFuture;
      if (!mounted ||
          generation != _generation ||
          !identical(_catalog, catalog)) {
        return;
      }
      if (catalog.status == ModelProviderCatalogStatus.loaded) {
        _projection = ComposerModelCatalogProjection.fromCatalog(
            catalog, familySelection);
        _metadataError = familyError;
      } else {
        _metadataError =
            catalog.error ?? familyError ?? StateError('metadata unavailable');
      }
      if (mounted && generation == _generation) setState(() {});
    } finally {
      _metadataLoading = false;
      if (mounted && generation == _generation) setState(() {});
    }
  }

  @override
  void dispose() {
    _generation++;
    _catalog?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => widget.builder(
          context,
          _projection,
          _metadataError,
          _metadataLoading,
          _refreshMetadata),
    );
  }
}

class _ModeMenu extends StatelessWidget {
  const _ModeMenu({required this.controller});
  final ComposerController controller;

  @override
  Widget build(BuildContext context) {
    final options = controller.options.modes;
    final selected = controller.config['mode'] as String?;
    final enabled = controller.canConfigureMode;
    // The exposed mode set identifies the Agent family (official FYe keys);
    // the model provider id is only a fallback heuristic.
    final family = familyForModeValues([for (final o in options) o.value]);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in options)
          _ModeOption(
            option: option,
            provider: controller.config['provider'] as String?,
            family: family,
            selected: option.value == selected,
            enabled: enabled,
          ),
      ],
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.option,
    required this.provider,
    required this.family,
    required this.selected,
    required this.enabled,
  });

  final ConfigOptionValue option;
  final String? provider;
  final String? family;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final label = modeLabel(context, option.value, option.name, provider, family);
    final description = modeDescription(context, option, provider, family);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      child: InkWell(
        key: ValueKey('composer-mode-option-${option.value}'),
        onTap: enabled
            ? () => Navigator.of(context).pop<String>(option.value)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LucideIcon(
                  modeIconForValue(option.value),
                  key: ValueKey('composer-mode-option-${option.value}-icon'),
                  size: 18,
                  color: ink.text.withValues(alpha: enabled ? 1 : .45),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        key: ValueKey(
                            'composer-mode-option-${option.value}-label'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink.text.withValues(alpha: enabled ? 1 : .45),
                          fontSize: 14,
                          height: 20 / 14,
                        ),
                      ),
                      if (description?.trim().isNotEmpty == true)
                        Text(
                          description!,
                          key: ValueKey(
                              'composer-mode-option-${option.value}-description'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink.subtlest
                                .withValues(alpha: enabled ? 1 : .45),
                            fontSize: 12,
                            height: 16 / 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  LucideIcon('check', size: 16, color: ink.subtlest),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelMenu extends StatelessWidget {
  const _ModelMenu({required this.controller, this.onManageModels});
  final ComposerController controller;
  final VoidCallback? onManageModels;

  @override
  Widget build(BuildContext context) {
    return _ModelMenuData(
      controller: controller,
      builder: (context, projection, metadataError, metadataLoading,
              refreshMetadata) =>
          _ModelMenuBody(
            controller: controller,
            projection: projection,
            metadataError: metadataError,
            metadataLoading: metadataLoading,
            refreshMetadata: refreshMetadata,
            onManageModels: onManageModels,
          ),
    );
  }
}

class _ModelMenuBody extends StatelessWidget {
  const _ModelMenuBody({
    required this.controller,
    required this.projection,
    required this.metadataError,
    required this.metadataLoading,
    required this.refreshMetadata,
    this.onManageModels,
  });
  final ComposerController controller;
  final ComposerModelCatalogProjection? projection;
  final Object? metadataError;
  final bool metadataLoading;
  final VoidCallback refreshMetadata;
  final VoidCallback? onManageModels;

  @override
  Widget build(BuildContext context) {
    final groups = controller.options.modelGroupsFor(projection);
    final selected = controller.options.model(controller.config)?.value;
    final enabled = controller.canConfigureModel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups)
          if (group.directItems)
            _DirectProviderGroup(
              group: group,
              selected: selected,
              enabled: enabled,
            )
          else
            _ProviderOption(
              controller: controller,
              groupId: group.id,
              label: group.label,
              badgeLabel: group.badgeLabel,
              items: group.items,
              visionModelValues: group.visionModelValues,
              projection: projection,
              selected: group.items.any((item) => item.value == selected),
              enabled: enabled,
            ),
        if (metadataError != null) ...[
          const Divider(height: 1),
          _RetryMetadataOption(
              onPressed: refreshMetadata, enabled: !metadataLoading),
        ],
        if (onManageModels != null) ...[
          const Divider(height: 1),
          _ManageModelsOption(onPressed: onManageModels!),
        ],
      ],
    );
  }
}

class _ProviderOption extends StatelessWidget {
  const _ProviderOption({
    required this.controller,
    required this.groupId,
    required this.label,
    this.badgeLabel,
    required this.items,
    required this.visionModelValues,
    required this.projection,
    required this.selected,
    required this.enabled,
  });

  final ComposerController controller;
  final String groupId;
  final String label;
  final String? badgeLabel;
  final List<ConfigOptionValue> items;
  final Set<String> visionModelValues;
  final ComposerModelCatalogProjection? projection;
  final bool selected;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    if (!enabled) return;
    final result = await showComposerPopover<String>(
      context,
      width: 192,
      maxHeight: 288,
      collisionPadding: 16,
      gap: 4,
      side: ComposerPopoverSide.right,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final group = controller.options
              .modelGroupsFor(projection)
              .where((candidate) => candidate.id == groupId)
              .firstOrNull;
          return _ModelItems(
            items: group?.items ?? items,
            selected: controller.options.model(controller.config)?.value,
            enabled: controller.canConfigureModel,
            visionModelValues: group?.visionModelValues ?? visionModelValues,
          );
        },
      ),
    );
    if (result != null && context.mounted) {
      Navigator.of(context).pop<String>(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      child: InkWell(
        key: ValueKey('composer-model-provider-$groupId'),
        onTap: enabled ? () => _open(context) : null,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink.text.withValues(alpha: enabled ? 1 : .45),
                      fontSize: 14,
                    ),
                  ),
                ),
                if (badgeLabel?.trim().isNotEmpty == true) ...[
                  const SizedBox(width: 6),
                  _ModelBadge(label: badgeLabel!),
                ],
                if (selected)
                  LucideIcon('check', size: 16, color: ink.subtlest)
                else
                  LucideIcon('chevron-right', size: 16, color: ink.subtlest),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelItems extends StatelessWidget {
  const _ModelItems({
    required this.items,
    required this.selected,
    required this.enabled,
    required this.visionModelValues,
  });
  final List<ConfigOptionValue> items;
  final String? selected;
  final bool enabled;
  final Set<String> visionModelValues;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items) ...[
          _ModelOption(
            item: item,
            selected: item.value == selected,
            enabled: enabled,
            supportsVisionInput: visionModelValues.contains(item.value),
          ),
        ],
      ],
    );
  }
}

class _ModelOption extends StatelessWidget {
  const _ModelOption({
    required this.item,
    required this.selected,
    required this.enabled,
    this.supportsVisionInput = false,
  });

  final ConfigOptionValue item;
  final bool selected;
  final bool enabled;
  final bool supportsVisionInput;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: item.name,
      child: InkWell(
        key: ValueKey('composer-model-option-${item.value}'),
        onTap: enabled
            ? () => Navigator.of(context).pop<String>(item.value)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                ink.text.withValues(alpha: enabled ? 1 : .45),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (supportsVisionInput) ...[
                        const SizedBox(width: 6),
                        LucideIcon(
                          'file-image',
                          key: ValueKey(
                              'composer-model-option-${item.value}-vision'),
                          size: 14,
                          color: ink.subtlest,
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  LucideIcon('check', size: 16, color: ink.subtlest),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Official direct provider groups render a labelled section followed by the
/// provider's models. Each model row remains the selectable item.
class _DirectProviderGroup extends StatelessWidget {
  const _DirectProviderGroup({
    required this.group,
    required this.selected,
    required this.enabled,
  });

  final ComposerModelGroup group;
  final String? selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: ValueKey('composer-model-provider-${group.id}'),
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  group.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink.subtlest,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (group.badgeLabel?.trim().isNotEmpty == true)
                _ModelBadge(label: group.badgeLabel!),
            ],
          ),
        ),
        for (final item in group.items)
          _ModelOption(
            item: item,
            selected: item.value == selected,
            enabled: enabled,
            supportsVisionInput: group.visionModelValues.contains(item.value),
          ),
      ],
    );
  }
}

class _ModelBadge extends StatelessWidget {
  const _ModelBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Container(
      key: ValueKey('composer-model-badge-$label'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: ink.hover,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: ink.subtlest, fontSize: 11, height: 14 / 11),
      ),
    );
  }
}

class _RetryMetadataOption extends StatelessWidget {
  const _RetryMetadataOption({required this.onPressed, required this.enabled});
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final label = uiText(context, '重试模型信息', 'Retry model metadata');
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkWell(
        key: const ValueKey('composer-model-metadata-retry'),
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(color: ink.text, fontSize: 14)),
                ),
                LucideIcon('refresh-cw', size: 16, color: ink.subtlest),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ManageModelsOption extends StatelessWidget {
  const _ManageModelsOption({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final label = uiText(context, '管理模型', 'Manage models');
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        key: const ValueKey('composer-manage-models'),
        onTap: () {
          Navigator.of(context).pop();
          onPressed();
        },
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(color: ink.text, fontSize: 14)),
                ),
                LucideIcon('settings', size: 16, color: ink.subtlest),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
