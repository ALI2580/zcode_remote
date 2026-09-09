import '../protocol/conversation.dart';

class WorkspaceDescriptor {
  const WorkspaceDescriptor(
      {required this.key, required this.title, required this.scope});
  final String key;
  final String title;
  final Map<String, dynamic> scope;
  static WorkspaceDescriptor? parse(Map<String, dynamic> raw) {
    String? nonempty(dynamic value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    final identity = nonempty(raw['workspaceIdentity']);
    final path = nonempty(raw['workspacePath']);
    final key = identity ??
        path ??
        nonempty(raw['workspaceKey']) ??
        nonempty(raw['key']) ??
        nonempty(raw['id']);
    if (key == null) return null;
    final basename = path
        ?.replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '')
        .split('/')
        .last;
    return WorkspaceDescriptor(
        key: key,
        title: nonempty(raw['name']) ??
            nonempty(raw['label']) ??
            nonempty(basename) ??
            identity ??
            '工作区',
        scope: {
          if (identity != null) 'workspaceIdentity': identity,
          if (path != null) 'workspacePath': path,
          if (identity == null && path == null) 'workspaceIdentity': key
        });
  }
}

/// Channel task lists and sessions-index snapshots are independent sources.
/// An empty or failed response from either one cannot erase the other.
class WorkspaceTaskCatalog {
  WorkspaceTaskCatalog(this.scope);
  final Map<String, dynamic> scope;
  List<SessionEntry> channel = [];
  List<SessionEntry> index = [];
  List<SessionEntry> pinned = [];
  List<SessionEntry> archived = [];
  List<SessionEntry> remote = [];
  final _latestPins = <String, bool>{};
  final _latestArchives = <String, bool>{};
  int _pinRevision = 0, _archiveRevision = 0;
  int get pinRevision => _pinRevision;
  int get archiveRevision => _archiveRevision;
  final _unreadOverrides = <String, bool>{};
  final _deleted = <String>{};
  final _archiveOverrides = <String, bool>{};
  final _pinOverrides = <String, bool>{};
  final _titleOverrides = <String, String>{};

  List<SessionEntry> parseChannel(dynamic result) {
    if (result is! List) return const [];
    return [
      for (final raw in result.whereType<Map>())
        if (belongsToWorkspace(raw, scope) &&
            (raw['taskId'] ?? raw['sessionId'] ?? raw['id']) != null)
          SessionEntry({
            ...raw.cast<String, dynamic>(),
            'sessionId': '${raw['taskId'] ?? raw['sessionId'] ?? raw['id']}',
            'phase':
                raw['displayStatus'] ?? raw['status'] ?? raw['phase'] ?? '',
            'lastActivityAt': raw['updatedAt'] is num
                ? raw['updatedAt']
                : raw['lastActivityAt'] ?? 0,
            'createdAt': raw['createdAt'] is num ? raw['createdAt'] : 0
          })
    ];
  }

  bool isPinned(String id) =>
      _pinOverrides[id] ??
      _latestPins[id] ??
      pinned.any((entry) => entry.sessionId == id);
  bool isArchived(String id) =>
      _archiveOverrides[id] ??
      _latestArchives[id] ??
      archived.any((entry) => entry.sessionId == id);
  void setArchived(String id, bool value) {
    _archiveRevision++;
    _archiveOverrides[id] = value;
    if (value) setPinned(id, false);
  }

  void setPinned(String id, bool value) {
    _pinRevision++;
    _pinOverrides[id] = value;
  }

  void setTitle(String id, String value) => _titleOverrides[id] = value;
  void setUnread(String id, bool value) => _unreadOverrides[id] = value;
  void remove(String id) => _deleted.add(id);

  void replacePinned(List<SessionEntry> entries, {int? requestRevision}) {
    if (requestRevision != null && requestRevision != _pinRevision) return;
    _pinRevision++;
    pinned = entries;
    final ids = entries.map((e) => e.sessionId).toSet();
    for (final task in _merged()) {
      final value = ids.contains(task.sessionId);
      _latestPins[task.sessionId] = value;
      if (_pinOverrides[task.sessionId] == value) {
        _pinOverrides.remove(task.sessionId);
      }
    }
  }

  void replaceArchived(List<SessionEntry> entries, {int? requestRevision}) {
    if (requestRevision != null && requestRevision != _archiveRevision) return;
    _archiveRevision++;
    archived = entries;
    final ids = entries.map((e) => e.sessionId).toSet();
    for (final task in _merged()) {
      final value = ids.contains(task.sessionId);
      _latestArchives[task.sessionId] = value;
      if (_archiveOverrides[task.sessionId] == value) {
        _archiveOverrides.remove(task.sessionId);
      }
    }
  }

  void replaceRemote(List<SessionEntry> entries) {
    // listWorkspaces supplies a full task projection; CCt removes false flags
    // instead of serializing false. Preserve explicit absence while merging.
    remote = [
      for (final entry in entries)
        SessionEntry({...entry.raw, 'unreadAt': entry.raw['unreadAt']})
    ];
    _pinRevision++;
    _archiveRevision++;
    for (final task in remote) {
      final id = task.sessionId;
      final pinned = task.raw['pinned'] == true;
      final archived = task.raw['archived'] == true;
      _latestPins[id] = pinned;
      _latestArchives[id] = archived;
      if (_pinOverrides[id] == pinned) _pinOverrides.remove(id);
      if (_archiveOverrides[id] == archived) _archiveOverrides.remove(id);
      if (_titleOverrides[id] == task.title) _titleOverrides.remove(id);
      if (task.raw.containsKey('unreadAt') &&
          _unreadOverrides[id] == (task.raw['unreadAt'] != null)) {
        _unreadOverrides.remove(id);
      }
    }
  }

  List<SessionEntry> get visible =>
      _merged().where((entry) => !isArchived(entry.sessionId)).toList();
  List<SessionEntry> get archiveList =>
      _merged().where((entry) => isArchived(entry.sessionId)).toList();
  List<SessionEntry> _merged() {
    final merged = <String, Map<String, dynamic>>{};
    // Newer projections win field-by-field; source order breaks equal-time
    // ties in favor of the live local index. An empty source never erases peers.
    final ordered = [...remote, ...channel, ...pinned, ...archived, ...index]
        .asMap()
        .entries
        .toList()
      ..sort((a, b) {
        final time = a.value.lastActivityAt.compareTo(b.value.lastActivityAt);
        return time != 0 ? time : a.key.compareTo(b.key);
      });
    for (final item in ordered) {
      final entry = item.value;
      final old = merged[entry.sessionId];
      merged[entry.sessionId] = {
        ...?old,
        ...entry.raw,
        if (entry.title.isEmpty && old?['title'] is String)
          'title': old!['title'],
        if (entry.phase.isEmpty && old?['phase'] is String)
          'phase': old!['phase'],
        if (entry.createdAt == 0 && old?['createdAt'] is num)
          'createdAt': old!['createdAt'],
      };
    }
    final values = [
      for (final item in merged.entries)
        if (!_deleted.contains(item.key))
          SessionEntry({
            ...item.value,
            if (_titleOverrides.containsKey(item.key))
              'title': _titleOverrides[item.key],
            if (_unreadOverrides.containsKey(item.key))
              'unreadAt': _unreadOverrides[item.key]! ? 1 : null,
          })
    ];
    values.sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
    return values;
  }
}

bool belongsToWorkspace(Map row, Map scope) {
  final expectedIdentity = scope['workspaceIdentity'];
  final identity = row['workspaceIdentity'];
  if (identity is String &&
      identity.isNotEmpty &&
      expectedIdentity is String &&
      expectedIdentity.isNotEmpty) {
    return identity == expectedIdentity;
  }
  final expectedPath = scope['workspacePath'];
  final path = row['workspacePath'];
  if (expectedPath is! String || path is! String || path.isEmpty) return true;
  String normalize(String value) {
    final clean = value.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    return RegExp(r'^[A-Za-z]:/').hasMatch(clean) ? clean.toLowerCase() : clean;
  }

  return normalize(expectedPath) == normalize(path);
}
