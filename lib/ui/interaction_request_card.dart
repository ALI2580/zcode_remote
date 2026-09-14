import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';

import '../state/interaction_requests.dart';
import 'theme.dart';

class InteractionRequestCard extends StatefulWidget {
  const InteractionRequestCard({super.key, required this.controller});

  final InteractionController controller;

  @override
  State<InteractionRequestCard> createState() => _InteractionRequestCardState();
}

class _InteractionRequestCardState extends State<InteractionRequestCard> {
  String _requestId = '';
  final _selected = <String, List<String>>{};
  final _custom = <String, TextEditingController>{};
  final _freeText = TextEditingController();
  Timer? _countdownTimer;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;
  int _questionIndex = 0;
  String? _questionDraftId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  InkTokens get ink => ZInk.of(Theme.of(context).colorScheme);

  @override
  void didUpdateWidget(InteractionRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = '${widget.controller.active?['interactionId'] ?? ''}';
    if (id == _requestId) return;
    _requestId = id;
    _selected.clear();
    for (final controller in _custom.values) {
      controller.dispose();
    }
    _custom.clear();
    _freeText.clear();
    _questionIndex = 0;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    widget.controller.removeListener(_onChanged);
    for (final controller in _custom.values) {
      controller.dispose();
    }
    _freeText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.controller.active;
    if (request == null) return const SizedBox.shrink();
    final payload =
        (request['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final id = '${request['interactionId'] ?? ''}';
    _syncQuestionDrafts(id, payload);
    final busy = widget.controller.resolvingIds.contains(id);
    final failure = widget.controller.failureFor(id);

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: .40),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                decoration: BoxDecoration(
                  color: ink.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: ink.border),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(payload),
                    if (failure != null) _failure(failure),
                    _autoResolutionBar(request, id, busy),
                    if (widget.controller.pendingCount > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '还有 ${widget.controller.pendingCount - 1} 个请求等待处理',
                          style: TextStyle(fontSize: 12, color: ink.subtlest),
                        ),
                      ),
                    if (payload['kind'] == 'permission')
                      _permissionBody(payload, id, busy)
                    else
                      _userInputBody(
                        payload,
                        id,
                        busy,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(Map<String, dynamic> payload) {
    final title = payload['toolName'] as String? ??
        (payload['kind'] == 'permission' ? '需要权限' : '需要输入');
    return Text(
      title,
      style:
          TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink.text),
    );
  }

  Widget _autoResolutionBar(
      Map<String, dynamic> request, String id, bool busy) {
    if (request['kind'] != 'userInput') return const SizedBox.shrink();
    final auto = (request['autoResolution'] as Map?)?.cast<String, dynamic>();
    if (auto == null) return const SizedBox.shrink();
    final state = auto['state'] as String? ?? '';
    if (state == 'snoozed') {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '自动结束已挂起',
                style: TextStyle(fontSize: 12, color: ink.subtlest),
              ),
            ),
          ],
        ),
      );
    }
    final visibleAt = (auto['visibleAt'] as num?)?.toInt() ?? 0;
    final deadlineAt = (auto['deadlineAt'] as num?)?.toInt() ?? 0;
    final total = deadlineAt - visibleAt;
    if (deadlineAt <= 0 || total <= 0 || _nowMs >= deadlineAt) {
      return const SizedBox.shrink();
    }
    if (_nowMs < visibleAt) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('自动结束等待中',
            style: TextStyle(fontSize: 12, color: ink.subtlest)),
      );
    }
    // Official uct(): max(1, floor(remaining seconds)); zero hides above.
    final remaining = math.max(1, ((deadlineAt - _nowMs) / 1000).floor());
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('自动结束剩余 ${remaining}s',
                    style: TextStyle(fontSize: 12, color: ink.subtlest)),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: ((deadlineAt - _nowMs) / total).clamp(0.0, 1.0),
                  minHeight: 3,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => unawaited(widget.controller.snoozeAutoResolution(id)),
            child: const Text('挂起'),
          ),
        ],
      ),
    );
  }

  Widget _failure(InteractionFailure failure) {
    final message = failure.error?.toString() ??
        [
          if (failure.status != null) failure.status!,
          if (failure.reasonCode != null) failure.reasonCode!,
        ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '请求未受理：$message',
        style: TextStyle(fontSize: 12, color: ink.diffRemoved),
      ),
    );
  }

  Widget _permissionBody(Map<String, dynamic> payload, String id, bool busy) {
    final detail = payload['detail'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${payload['summary'] ?? ''}',
            style: TextStyle(fontSize: 14, color: ink.text)),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              const JsonEncoder.withIndent('  ').convert(detail),
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 12, color: ink.subtlest),
            ),
          ),
        const SizedBox(height: 12),
        for (final option in _maps(payload['options']))
          _optionButton(
            label: '${option['label'] ?? option['optionId'] ?? ''}',
            busy: busy,
            onTap: () => unawaited(
              widget.controller.resolve(
                id,
                optionId: '${option['optionId'] ?? ''}',
              ),
            ),
          ),
      ],
    );
  }

  Widget _userInputBody(Map<String, dynamic> payload, String id, bool busy) {
    final questions = _maps(payload['questions']);
    if (questions.isNotEmpty) {
      return _questionBody(questions, id, busy, payload: payload);
    }
    final options = _maps(payload['options']);
    final freeText = payload['freeText'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${payload['prompt'] ?? ''}',
            style: TextStyle(fontSize: 14, color: ink.text)),
        if (freeText) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _freeText,
            enabled: !busy,
            maxLines: 4,
            decoration: const InputDecoration(hintText: '输入回复'),
          ),
        ],
        const SizedBox(height: 12),
        for (final option in options)
          _optionButton(
            label: '${option['label'] ?? option['optionId'] ?? ''}',
            busy: busy,
            onTap: () => unawaited(
              widget.controller.resolve(
                id,
                optionId: '${option['optionId'] ?? ''}',
              ),
            ),
          ),
        if (freeText || options.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(
              onPressed: busy
                  ? null
                  : () {
                      final text = _freeText.text.trim();
                      if (freeText) {
                        if (text.isNotEmpty) {
                          unawaited(
                              widget.controller.resolve(id, freeText: text));
                        }
                        return;
                      }
                      unawaited(
                          widget.controller.resolve(id, action: 'accept'));
                    },
              child: const Text('确认'),
            ),
          ),
      ],
    );
  }

  Widget _questionBody(
    List<Map<String, dynamic>> questions,
    String id,
    bool busy, {
    required Map<String, dynamic> payload,
  }) {
    _restoreQuestionDrafts(id, questions, payload: payload);
    final index = _questionIndex.clamp(0, questions.length - 1);
    final question = questions[index];
    final key = '$index:${question['question'] ?? ''}';
    final multi = question['multiSelect'] == true;
    final selected = _selected[key] ?? const <String>[];
    final custom = _custom.putIfAbsent(key, TextEditingController.new);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (question['header'] != null)
          Text('${question['header']}',
              style: TextStyle(fontSize: 12, color: ink.subtlest)),
        Text('${question['question'] ?? ''}',
            style: TextStyle(fontSize: 14, color: ink.text)),
        const SizedBox(height: 12),
        for (final option in _maps(question['options']))
          _optionButton(
            label: '${option['label'] ?? option['value'] ?? ''}',
            busy: busy,
            selected: selected.contains('${option['value'] ?? ''}'),
            onTap: () {
              final value = '${option['value'] ?? ''}';
              setState(() {
                _selected[key] = multi
                    ? (selected.contains(value)
                        ? selected.where((v) => v != value).toList()
                        : [...selected, value])
                    : [value];
              });
              if (!multi && index < questions.length - 1) {
                setState(() => _questionIndex = index + 1);
              }
            },
          ),
        TextField(
          controller: custom,
          enabled: !busy,
          decoration: const InputDecoration(hintText: '自定义回复'),
        ),
        if (index > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              onPressed: busy ? null : () => setState(() => _questionIndex--),
              child: const Text('上一题'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton(
            onPressed: busy || selected.isEmpty && custom.text.trim().isEmpty
                ? null
                : () {
                    if (index < questions.length - 1) {
                      setState(() => _questionIndex = index + 1);
                      return;
                    }
                    unawaited(widget.controller.resolve(
                      id,
                      action: 'accept',
                      content: _questionContent(questions),
                    ));
                  },
            child: Text(index == questions.length - 1 ? '确认' : '下一题'),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _maps(Object? raw) => (raw as List? ?? const [])
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .toList();

  void _syncQuestionDrafts(String id, Map<String, dynamic> payload) {
    if (id == _requestId) return;
    _requestId = id;
    _selected.clear();
    for (final controller in _custom.values) {
      controller.dispose();
    }
    _custom.clear();
    _freeText.clear();
    final questions = _maps(payload['questions']);
    if (questions.isEmpty) {
      _questionDraftId = id;
      return;
    }
    _restoreQuestionDrafts(id, questions, payload: payload);
  }

  void _restoreQuestionDrafts(
    String id,
    List<Map<String, dynamic>> questions, {
    Map<String, dynamic>? payload,
  }) {
    if (_questionDraftId == id) return;
    _questionDraftId = id;
    _questionIndex = 0;
    final drafts =
        ((payload?['answerDrafts'] as Map?)?.cast<String, dynamic>() ??
            const {});
    final parsedIndex =
        int.tryParse('${payload?['currentQuestionIndex'] ?? 0}');
    _questionIndex = parsedIndex == null
        ? 0
        : parsedIndex.clamp(0, questions.length - 1).toInt();
    for (var i = 0; i < questions.length; i++) {
      final raw = drafts['answer_$i'] ?? drafts['$i'] ?? const <String>[];
      final values = raw is List
          ? raw
              .map((value) => '$value')
              .where((value) => value.isNotEmpty)
              .toList()
          : <String>[];
      final key = '$i:${questions[i]['question'] ?? ''}';
      _selected[key] = values;
      final customValues = values
          .where((value) => !_maps(questions[i]['options'])
              .any((option) => '${option['value'] ?? ''}' == value))
          .join(', ');
      if (customValues.isNotEmpty) {
        _custom.putIfAbsent(key, TextEditingController.new).text = customValues;
      }
    }
  }

  Map<String, dynamic> _questionContent(List<Map<String, dynamic>> questions) {
    final answers = <String, String>{};
    final indexedAnswers = <String, dynamic>{};
    for (var i = 0; i < questions.length; i++) {
      final question = questions[i];
      final key = '$i:${question['question'] ?? ''}';
      final custom = _custom[key]?.text.trim() ?? '';
      final values = [...?_selected[key], if (custom.isNotEmpty) custom];
      if (values.isEmpty) continue;
      final questionText = '${question['question'] ?? ''}';
      answers[questionText] = values.join(', ');
      indexedAnswers['answer_$i'] =
          question['multiSelect'] == true ? values : values.first;
    }
    final content = <String, dynamic>{
      'answers': answers,
      ...indexedAnswers,
    };
    if (questions.length == 1) {
      final only = _selected[_keyFor(questions, 0)] ?? const <String>[];
      final custom = _custom[_keyFor(questions, 0)]?.text.trim() ?? '';
      final values = [...only, if (custom.isNotEmpty) custom];
      if (values.isNotEmpty) {
        content['answer'] =
            questions.single['multiSelect'] == true ? values : values.first;
      }
    }
    return content;
  }

  String _keyFor(List<Map<String, dynamic>> questions, int index) =>
      '$index:${questions[index]['question'] ?? ''}';

  Widget _optionButton({
    required String label,
    required bool busy,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? ink.hover : null,
        ),
        child: Text(label),
      ),
    );
  }
}
