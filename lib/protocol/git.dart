import 'channel_client.dart';
import 'zemote_client.dart';

/// Read-only view of the official `git.refresh` summary. Mutating methods are
/// intentionally not exposed here.
class GitSummary {
  const GitSummary({
    required this.isGitAvailable,
    required this.isRepository,
    required this.isDirty,
    required this.ahead,
    required this.behind,
    this.workspacePath,
    this.repoRoot,
    this.branchName,
    this.trackingBranchName,
    this.headRefType = 'branch',
  });

  factory GitSummary.fromRaw(Object? raw) {
    final map =
        raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};
    num intValue(String key) => map[key] is num ? map[key] as num : 0;
    String? strValue(String key) =>
        map[key] is String && (map[key] as String).trim().isNotEmpty
            ? map[key] as String
            : null;
    return GitSummary(
      isGitAvailable: map['isGitAvailable'] == true,
      isRepository: map['isRepository'] == true,
      isDirty: map['isDirty'] == true,
      ahead: intValue('ahead').toInt(),
      behind: intValue('behind').toInt(),
      workspacePath: strValue('workspacePath'),
      repoRoot: strValue('repoRoot'),
      branchName: strValue('branchName'),
      trackingBranchName: strValue('trackingBranchName'),
      headRefType: strValue('headRefType') ?? 'branch',
    );
  }

  final bool isGitAvailable;
  final bool isRepository;
  final bool isDirty;
  final int ahead;
  final int behind;
  final String? workspacePath;
  final String? repoRoot;
  final String? branchName;
  final String? trackingBranchName;
  final String? headRefType;

  bool get available => isGitAvailable && isRepository;
  String get displayBranchName =>
      headRefType == 'detached' ? 'HEAD detached' : branchName ?? '';
}

class GitClient {
  const GitClient({required this.session, required this.scope});

  final BridgeSession session;
  final Map<String, dynamic> scope;

  Future<dynamic> refresh({
    bool includeIdentity = false,
    bool includeBranchComparison = false,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await session.waitHealthy(timeout: timeout);
    return session.channels.call(
      Channels.git,
      'refresh',
      [
        {
          'workspacePath': scope['workspacePath'],
          if (scope['workspaceIdentity'] != null)
            'workspaceIdentity': scope['workspaceIdentity'],
          'includeIdentity': includeIdentity,
          'includeBranchComparison': includeBranchComparison,
        }
      ],
      timeout: timeout,
    );
  }
}
