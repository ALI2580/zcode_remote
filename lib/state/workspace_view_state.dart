import 'recovery_collections.dart';

/// Layout preferences belong to one task, independently of its route lifetime.
class WorkspaceViewState {
  void Function()? onChanged;
  bool _sidebarCollapsed = false, _panelOpen = false;
  String _panelTab = 'summary';
  late final expandedProjects = RecoverySet<String>(() => onChanged?.call());
  bool get sidebarCollapsed => _sidebarCollapsed;
  set sidebarCollapsed(bool v) {
    if (_sidebarCollapsed == v) return;
    _sidebarCollapsed = v;
    onChanged?.call();
  }

  bool get panelOpen => _panelOpen;
  set panelOpen(bool v) {
    if (_panelOpen == v) return;
    _panelOpen = v;
    onChanged?.call();
  }

  String get panelTab => _panelTab;
  set panelTab(String v) {
    if (_panelTab == v) return;
    _panelTab = v;
    onChanged?.call();
  }

  Map<String, dynamic> toJson() => {
        'sidebarCollapsed': sidebarCollapsed,
        'panelOpen': panelOpen,
        'panelTab': panelTab,
        'expandedProjects': expandedProjects.toList()
      };
  static WorkspaceViewState fromJson(Map raw) {
    final state = WorkspaceViewState()
      ..sidebarCollapsed = raw['sidebarCollapsed'] == true
      ..panelOpen = raw['panelOpen'] == true;
    if (raw['panelTab'] case final String v) state.panelTab = v;
    if (raw['expandedProjects'] case final List v) {
      state.expandedProjects.addAll(v.whereType<String>());
    }
    return state;
  }
}

/// Sidebar navigation belongs to the selected device, not the open task.
class SidebarViewState {
  void Function()? onChanged;
  bool _archived = false;
  bool get archived => _archived;
  set archived(bool v) {
    if (_archived == v) return;
    _archived = v;
    onChanged?.call();
  }

  late final expandedProjects = RecoverySet<String>(() => onChanged?.call());
  Map<String, dynamic> toJson() =>
      {'archived': archived, 'expandedProjects': expandedProjects.toList()};
  static SidebarViewState fromJson(Map raw) {
    final state = SidebarViewState()..archived = raw['archived'] == true;
    if (raw['expandedProjects'] case final List v) {
      state.expandedProjects.addAll(v.whereType<String>());
    }
    return state;
  }
}
