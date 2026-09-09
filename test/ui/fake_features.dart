import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'fake_workspace.dart';

class FeatureChannels extends ChannelClient {
  FeatureChannels() : super(sendBody: (_) {});
  final calls = <({String channel, String method, List<Object?> args})>[];
  FutureOr<dynamic> Function(String channel, String method, List<Object?> args)?
      handler;
  @override
  Future<dynamic> call(String channel, String method, List<Object?> args,
      {Duration timeout = const Duration(seconds: 30)}) async {
    calls.add((channel: channel, method: method, args: args));
    if (handler == null && method == 'getCodingPlanResetStatus') {
      return {
        'availableFiveHourResets': [],
        'availableWeekResets': [],
        'hasUnreadHistory': false
      };
    }
    return handler == null
        ? (method.startsWith('list') ? [] : {})
        : await handler!(channel, method, args);
  }
}

class FeatureBridge extends FakeBridge {
  @override
  final FeatureChannels channels = FeatureChannels();
  late final _featureTransport = FeatureTransport(this);
  @override
  FeatureTransport get conversationTransport => _featureTransport;
}

class FeatureTransport extends FakeConversationTransport {
  FeatureTransport(super.session);
  Map<String, dynamic> families = {
    'modelProviderFamilyModes': {'bigmodel': 'oauth', 'zai': 'oauth'},
    'modelProviderFamilySelectedKeys': {
      'bigmodel': 'coding-plan:builtin:bigmodel-coding-plan',
      'zai': 'coding-plan:builtin:zai-start-plan',
    },
  };
  Future<Map<String, dynamic>> Function()? familyHandler;
  int familyReads = 0;
  final quotaCalls = <Map<String, dynamic>>[];
  Future<dynamic> Function(String, String?, String?)? quotaHandler;
  Future<dynamic> Function(String)? teamProductsHandler;
  final teamProductCalls = <String>[];
  final uploads = <Map<String, dynamic>>[];
  Future<void> Function()? uploadHandler;
  List<Map<String, dynamic>> files = const [
    {
      'name': 'main.dart',
      'relativePath': 'lib/main.dart',
      'path': 'D:/Synthetic/lib/main.dart',
      'type': 'file'
    },
    {
      'name': 'lib',
      'relativePath': 'lib',
      'path': 'D:/Synthetic/lib',
      'type': 'directory'
    },
  ];
  List<Map<String, dynamic>> skillItems = const [
    {
      'id': 'user-skill',
      'name': 'review-code',
      'path': '/user/review.md',
      'scope': 'user',
      'description': 'User version'
    },
    {
      'id': 'workspace-skill',
      'name': 'review-code',
      'path': 'skills/review.md',
      'scope': 'workspace',
      'description': 'Workspace version'
    },
  ];
  List<Map<String, dynamic>> plugins = const [
    {
      'pluginId': 'demo@official',
      'name': 'Demo plugin',
      'enabled': true,
      'description': 'Tools for the task',
      'conflictingPluginIds': []
    },
    {
      'pluginId': 'conflict@other',
      'name': 'Conflicting plugin',
      'enabled': true,
      'conflictingPluginIds': ['demo@official']
    },
  ];
  Future<List<Map<String, dynamic>>> Function()? filesHandler;
  int fileReads = 0;
  @override
  Future<WorkspacePrep> prepareWorkspace({bool refresh = false}) async {
    if (prepHandler != null) return prepHandler!();
    final options = (composerPrepFixture['configOptions'] as List)
        .cast<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    options[0]['options'] = [
      ...options[0]['options'] as List,
      for (final provider in [
        'builtin:bigmodel-coding-plan',
        'builtin:zai-start-plan'
      ])
        {
          'value': '$provider/GLM-5.2',
          'name': 'GLM-5.2',
          'modelProviderId': provider,
          'modelProviderName':
              provider.startsWith('builtin:bigmodel') ? 'BigModel' : 'Z.ai',
          'modelThoughtLevels': ['high', 'max'],
          'modelDefaultThoughtLevel': 'max'
        }
    ];
    return WorkspacePrep.fromRaw({
      'configOptions': options,
      'slashCommands': [
        for (final name in ['plan', 'compact', 'goal', 'review'])
          {'name': name, 'description': 'Run $name', 'source': 'runtime'}
      ]
    });
  }

  @override
  Future<Map<String, dynamic>> providerFamilySelection() async {
    familyReads++;
    return familyHandler == null ? families : await familyHandler!();
  }

  @override
  Future<dynamic> teamPlanProducts(String family) async {
    teamProductCalls.add(family);
    return teamProductsHandler == null
        ? {'productList': []}
        : await teamProductsHandler!(family);
  }

  @override
  Future<dynamic> entitlementSnapshot(String providerId,
      {String? organizationId, String? projectId}) async {
    quotaCalls.add({
      'provider': providerId,
      'organizationId': organizationId,
      'projectId': projectId
    });
    if (quotaHandler != null) {
      return quotaHandler!(providerId, organizationId, projectId);
    }
    return quotaFixture(providerId);
  }

  @override
  Future<List<Map<String, dynamic>>> workspaceFiles() async {
    fileReads++;
    return filesHandler == null ? files : await filesHandler!();
  }

  @override
  Future<List<Map<String, dynamic>>> skillReferences(String? sessionId) async =>
      skillItems;
  @override
  Future<List<Map<String, dynamic>>> pluginReferences(
          String? sessionId) async =>
      plugins;
  @override
  Future<List<Map<String, dynamic>>> sessionReferences() async => [
        {
          'taskId': 'other-task',
          'title': 'Other task',
          'workspacePath': 'D:/Synthetic'
        }
      ];
  @override
  Future<Map<String, dynamic>> attachmentPut(String sessionId,
      {required String fileName,
      required String mime,
      required Uint8List bytes,
      void Function(double progress)? onProgress,
      bool Function()? isCancelled}) async {
    uploads.add({
      'sessionId': sessionId,
      'fileName': fileName,
      'mime': mime,
      'bytes': bytes.length
    });
    onProgress?.call(.5);
    await uploadHandler?.call();
    if (isCancelled?.call() == true) throw StateError('cancelled');
    onProgress?.call(1);
    return {
      'ref': 'synthetic:$sessionId:$fileName',
      'fileName': fileName,
      'mime': mime,
      'bytes': bytes.length
    };
  }
}

Map<String, dynamic> quotaFixture(String provider, {double used = 23}) => {
      'provider': {'id': provider},
      'context': {'scope': 'personal'},
      'quota': {
        'level': 'pro',
        'limits': [
          {
            'type': 'TOKENS_LIMIT',
            'unit': 3,
            'number': 5,
            'percentage': used,
            'nextResetTime': 1790000000000
          },
          {
            'type': 'CREDIT_LIMIT',
            'unit': 6,
            'percentage': 5,
            'nextResetTime': 1790500000000
          },
          {'type': 'TIME_LIMIT', 'unit': 5, 'number': 1, 'percentage': 0},
        ]
      },
      'mcpQuota': {
        'aggregate': {
          'type': 'TIME_LIMIT',
          'percentage': 10,
          'nextResetTime': 1790080000000
        }
      },
    };
