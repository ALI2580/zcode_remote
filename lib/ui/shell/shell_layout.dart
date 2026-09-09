import 'dart:ui' show DisplayFeatureType;
import 'package:flutter/material.dart';
import '../../state/client_preferences.dart';
import '../official_icons.dart';
import '../theme.dart';

class ShellGeometry {
  const ShellGeometry(
      {required this.sidebarWidth,
      required this.showSidebar,
      required this.panelWidth,
      required this.panelIsOverlay,
      this.hingeWidth = 0});
  final double sidebarWidth;
  final bool showSidebar;
  final double panelWidth;
  final bool panelIsOverlay;
  final double hingeWidth;
  static ShellGeometry resolve(double width, double scale,
      {required bool sidebarCollapsed, required bool panelOpen, Rect? hinge}) {
    final sidebar = width >= 1000 ? 264.0 : 224.0;
    final minimumChat = 360 * scale.clamp(1.0, 2.0);
    final panel = (288 * scale.clamp(1.0, 1.4)).clamp(288.0, 400.0);
    if (hinge != null &&
        hinge.width > 0 &&
        hinge.left >= 240 &&
        width - hinge.right >= 320) {
      return ShellGeometry(
          sidebarWidth: hinge.left,
          showSidebar: !sidebarCollapsed,
          panelWidth: width - hinge.right,
          panelIsOverlay: true,
          hingeWidth: hinge.width);
    }
    return ShellGeometry(
        sidebarWidth: sidebar,
        showSidebar: !sidebarCollapsed &&
            width >= 640 &&
            width >= sidebar + minimumChat + (panelOpen ? panel : 0),
        panelWidth: panel,
        panelIsOverlay: width < minimumChat + panel);
  }
}

class ShellIconButton extends StatelessWidget {
  const ShellIconButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed,
      this.selected = false});
  final String icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Tooltip(
        message: label,
        child: SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
                tooltip: label,
                onPressed: onPressed,
                padding: const EdgeInsets.all(12),
                style: IconButton.styleFrom(
                    backgroundColor: selected ? ink.hover : null,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                icon: LucideIcon(icon,
                    size: 16,
                    color: onPressed == null ? ink.subtlest : ink.text))));
  }
}

/// A stable conversation subtree across width, keyboard and panel changes.
/// Navigation history is owned by Flutter routes, so predictive back can
/// reveal the actual previous task and its unchanged draft.
class WorkspaceShellLayout extends StatefulWidget {
  const WorkspaceShellLayout(
      {super.key,
      required this.title,
      required this.project,
      required this.sidebar,
      required this.conversation,
      required this.sidebarCollapsed,
      required this.onSidebarCollapsed,
      this.panel,
      this.onClosePanel,
      this.actions = const [],
      this.onMore,
      this.panelOpen = true});
  final String title;
  final String project;
  final Widget sidebar;
  final Widget conversation;
  final bool sidebarCollapsed;
  final ValueChanged<bool> onSidebarCollapsed;
  final Widget? panel;
  final bool panelOpen;
  final VoidCallback? onClosePanel;
  final List<Widget> actions;
  final VoidCallback? onMore;
  @override
  State<WorkspaceShellLayout> createState() => _WorkspaceShellLayoutState();
}

class _WorkspaceShellLayoutState extends State<WorkspaceShellLayout> {
  final _scaffold = GlobalKey<ScaffoldState>();
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final features = media.displayFeatures;
      final hinge = features
          .where((feature) =>
              (feature.type == DisplayFeatureType.hinge ||
                  feature.type == DisplayFeatureType.fold) &&
              feature.bounds.width > 0 &&
              feature.bounds.height > feature.bounds.width)
          .firstOrNull
          ?.bounds;
      final panelOpen = widget.panel != null && widget.panelOpen;
      final geometry = ShellGeometry.resolve(
          constraints.maxWidth - media.padding.horizontal, scale,
          sidebarCollapsed: widget.sidebarCollapsed,
          panelOpen: panelOpen,
          hinge: hinge?.shift(Offset(-media.padding.left, 0)));
      final sidebarWidth = geometry.showSidebar ? geometry.sidebarWidth : 0.0;
      return Scaffold(
          key: _scaffold,
          backgroundColor: ink.background,
          drawerEnableOpenDragGesture: !geometry.showSidebar && !panelOpen,
          onDrawerChanged: (open) {
            if (open && panelOpen) widget.onClosePanel?.call();
          },
          drawer: geometry.showSidebar
              ? null
              : Drawer(
                  width: constraints.maxWidth.clamp(0, 300),
                  shape: const RoundedRectangleBorder(),
                  backgroundColor: ink.surface,
                  child: SafeArea(child: widget.sidebar)),
          body: SafeArea(
              child: Row(children: [
            SizedBox(
                width: sidebarWidth,
                child: geometry.showSidebar
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                            color: ink.surface,
                            border:
                                Border(right: BorderSide(color: ink.border))),
                        child: widget.sidebar)
                    : null),
            SizedBox(
                width: geometry.hingeWidth > 0
                    ? geometry.hingeWidth +
                        (geometry.showSidebar ? 0 : geometry.sidebarWidth)
                    : 0),
            Expanded(
                key: const ValueKey('workspace-main'),
                child: Column(children: [
                  Container(
                      key: const ValueKey('official-task-header'),
                      constraints: const BoxConstraints(minHeight: 48),
                      decoration: BoxDecoration(
                          border:
                              Border(bottom: BorderSide(color: ink.border))),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(children: [
                        ShellIconButton(
                            icon: 'panel-left',
                            label:
                                uiText(context, '项目与任务', 'Projects and tasks'),
                            onPressed: () {
                              if (geometry.showSidebar) {
                                widget.onSidebarCollapsed(true);
                              } else if (constraints.maxWidth >= 640 &&
                                  !panelOpen &&
                                  widget.sidebarCollapsed) {
                                widget.onSidebarCollapsed(false);
                              } else {
                                _scaffold.currentState?.openDrawer();
                              }
                            }),
                        Expanded(
                            child: Row(children: [
                          Flexible(
                              child: Text(widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: ink.text,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500))),
                          if (constraints.maxWidth - sidebarWidth >= 560)
                            Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                    color: ink.hover,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      LucideIcon('folder',
                                          size: 14, color: ink.subtlest),
                                      const SizedBox(width: 5),
                                      ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              maxWidth: 150),
                                          child: Text(widget.project,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: ink.subtlest,
                                                  fontSize: 12)))
                                    ])),
                        ])),
                        if (widget.onMore != null)
                          ShellIconButton(
                              icon: 'ellipsis',
                              label: uiText(context, '更多', 'More'),
                              onPressed: widget.onMore),
                        ...widget.actions,
                      ])),
                  Expanded(
                      child: LayoutBuilder(
                          builder: (context, workConstraints) =>
                              Stack(children: [
                                Row(children: [
                                  Expanded(
                                      child: ExcludeFocus(
                                          excluding: panelOpen &&
                                              geometry.panelIsOverlay,
                                          child: ExcludeSemantics(
                                              excluding: panelOpen &&
                                                  geometry.panelIsOverlay,
                                              child: IgnorePointer(
                                                  ignoring: panelOpen &&
                                                      geometry.panelIsOverlay,
                                                  child:
                                                      widget.conversation)))),
                                  SizedBox(
                                      width:
                                          panelOpen && !geometry.panelIsOverlay
                                              ? geometry.panelWidth
                                              : 0),
                                ]),
                                Positioned(
                                    top: 0,
                                    bottom: 0,
                                    right: 0,
                                    width: geometry.panelIsOverlay
                                        ? workConstraints.maxWidth
                                        : geometry.panelWidth,
                                    child: ExcludeFocus(
                                        excluding: !panelOpen,
                                        child: Offstage(
                                            offstage: !panelOpen,
                                            child: widget.panel == null
                                                ? const SizedBox.shrink()
                                                : _panel(context, ink)))),
                              ]))),
                ])),
          ])));
    });
  }

  Widget _panel(BuildContext context, InkTokens ink) => DecoratedBox(
      decoration: BoxDecoration(
          color: ink.surface,
          border: Border(left: BorderSide(color: ink.border))),
      child: Column(children: [
        Align(
            alignment: Alignment.centerRight,
            child: ShellIconButton(
                icon: 'x',
                label: uiText(context, '关闭面板', 'Close panel'),
                onPressed: widget.onClosePanel)),
        Expanded(child: widget.panel!)
      ]));
}
