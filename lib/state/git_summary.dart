import 'package:flutter/foundation.dart';

import '../protocol/git.dart';
import '../protocol/zemote_client.dart';

/// Loads the workspace git summary for the official top-bar branch entry.
/// Only `git.refresh` is called; branch switching, staging and commits stay
/// outside this controller.
class GitSummaryController extends ChangeNotifier {
  GitSummaryController({required this.session, required this.scope});

  final BridgeSession session;
  final Map<String, dynamic> scope;

  int _generation = 0;
  bool _disposed = false;
  bool _loading = false;
  Object? _error;
  GitSummary? _summary;

  bool get loading => _loading;
  Object? get error => _error;
  GitSummary? get summary => _summary;

  String get scopeKey =>
      '${scope['workspaceIdentity'] ?? scope['workspacePath'] ?? ''}';

  Future<void> refresh() async {
    if (_disposed) return;
    if ((scope['workspacePath'] as String?)?.trim().isEmpty == true) {
      _generation++;
      _loading = false;
      _summary = null;
      _error = null;
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    _loading = true;
    notifyListeners();
    try {
      final raw = await GitClient(session: session, scope: scope).refresh();
      if (_disposed || generation != _generation) return;
      _summary = GitSummary.fromRaw(raw is Map ? raw['summary'] : null);
      _error = null;
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _error = error;
    } finally {
      if (!_disposed && generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
