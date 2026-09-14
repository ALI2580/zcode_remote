import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import '../state/client_preferences.dart';
import '../state/conversation_view_state.dart';
import 'official_icons.dart';
import 'conversation_layout.dart';

/// Keeps a visible message anchored across streaming, folding and pagination.
class ConversationViewport extends StatefulWidget {
  const ConversationViewport(
      {super.key,
      required this.view,
      required this.ids,
      required this.itemBuilder,
      this.onLoadOlder,
      this.loadingOlder = false});
  final ConversationViewState view;
  final List<String> ids;
  final IndexedWidgetBuilder itemBuilder;
  final VoidCallback? onLoadOlder;
  final bool loadingOlder;

  @override
  State<ConversationViewport> createState() => _ConversationViewportState();
}

/// P2-viewport deterministic counters (references/optimization/
/// performance-todolist.md): [childIndexProbeCalls] counts
/// findChildIndexCallback invocations, [childIndexProbeEntries] the
/// `_items` entries scanned inside them (O(1) after the reverse-map fix),
/// and [captureScans] the ids iterated by anchor capture.
int viewportChildIndexProbeCalls = 0;
int viewportChildIndexProbeEntries = 0;
int viewportCaptureScans = 0;
int viewportIndexOfScans = 0;

class _ConversationViewportState extends State<ConversationViewport> {
  late final ScrollController _scroll;
  final _list = ListController();
  final _viewport = GlobalKey();
  final _items = <String, GlobalKey>{};
  bool _scheduled = false;
  bool _adjusting = false;
  bool _capturePending = false;

  // P2-viewport: findChildIndexCallback used to run two O(ids) scans per
  // visible child per rebuild (linear _items sweep + ids.indexOf). The key
  // now resolves through the `_idByKey` reverse map (maintained where the
  // forward map is filled), and the index through `_indexById`, rebuilt
  // lazily once per ids list instance. putIfAbsent keeps the FIRST index
  // for an id, matching the previous indexOf semantics.
  final _idByKey = <GlobalKey, String>{};
  List<String>? _indexSource;
  late final Map<String, int> _indexById = <String, int>{};

  Map<String, int> _indexOfId() {
    if (!identical(widget.ids, _indexSource)) {
      _indexById.clear();
      for (var i = 0; i < widget.ids.length; i++) {
        _indexById.putIfAbsent(widget.ids[i], () => i);
      }
      _indexSource = widget.ids;
    }
    return _indexById;
  }

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(
        initialScrollOffset: widget.view.pixels, keepScrollOffset: false);
    _scroll.addListener(_onScroll);
    _list.addListener(_restoreAfterLayout);
  }

  void _capture() {
    if (!_scroll.hasClients) return;
    widget.view.pixels = _scroll.offset;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    for (final id in widget.ids) {
      viewportCaptureScans++;
      final box = _items[id]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final offset = box.localToGlobal(Offset.zero).dy - top;
      if (offset + box.size.height > 0 && offset < viewport.size.height) {
        widget.view.anchor = id;
        widget.view.anchorOffset = offset;
        break;
      }
    }
  }

  void _onScroll() {
    if (_adjusting ||
        !_scroll.hasClients ||
        _scroll.position.userScrollDirection == ScrollDirection.idle) {
      return;
    }
    // Only real user scrolling may change following. Layout growth and our
    // own jumpTo/animateTo never opt the reader back in.
    final following = _scroll.position.extentAfter <= 1;
    if (following != widget.view.following) {
      setState(() => widget.view.following = following);
    }
    // Scroll listeners run before layout. Capture the painted position at
    // frame end, otherwise the previous anchor would undo this user's drag.
    widget.view.pixels = _scroll.offset;
    _capturePending = true;
    _restoreAfterLayout();
  }

  void _restoreAfterLayout() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      if (_capturePending) {
        _capturePending = false;
        _capture();
        return;
      }
      // A resize during an active drag must not fight the pointer.
      if (_scroll.position.userScrollDirection != ScrollDirection.idle) return;
      final view = widget.view;
      final anchorIndex = widget.ids.indexOf(view.anchor ?? '');
      final anchorBox = _items[view.anchor]?.currentContext?.findRenderObject();
      if (!view.following &&
          anchorIndex >= 0 &&
          (anchorBox is! RenderBox || !anchorBox.hasSize) &&
          _list.isAttached) {
        // Restore by index first, even if this variable-height message has
        // never been laid out. The next frame restores its exact local offset.
        _adjusting = true;
        _list.jumpToItem(
            index: anchorIndex + 1,
            scrollController: _scroll,
            alignment: 0,
            rect: Rect.fromLTWH(0, -view.anchorOffset, 1, 1));
        _adjusting = false;
        _restoreAfterLayout();
        return;
      }
      var target =
          view.following ? _scroll.position.maxScrollExtent : view.pixels;
      final box = _items[view.anchor]?.currentContext?.findRenderObject();
      final viewport = _viewport.currentContext?.findRenderObject();
      if (!view.following &&
          box is RenderBox &&
          box.hasSize &&
          viewport is RenderBox) {
        target = _scroll.offset +
            box.localToGlobal(Offset.zero).dy -
            viewport.localToGlobal(Offset.zero).dy -
            view.anchorOffset;
      }
      target = target.clamp(0.0, _scroll.position.maxScrollExtent);
      _adjusting = true;
      if ((_scroll.offset - target).abs() > .5) _scroll.jumpTo(target);
      _adjusting = false;
    });
  }

  @override
  void dispose() {
    _list.removeListener(_restoreAfterLayout);
    _list.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _restoreAfterLayout();
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _restoreAfterLayout();
        return false;
      },
      child: Stack(children: [
        SuperListView.builder(
            key: _viewport,
            controller: _scroll,
            listController: _list,
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: widget.ids.length + 1,
            findChildIndexCallback: (key) {
              viewportChildIndexProbeCalls++;
              final id = _idByKey[key];
              viewportChildIndexProbeEntries++;
              final index = id == null ? -1 : _indexOfId()[id] ?? -1;
              return index < 0 ? null : index + 1;
            },
            itemBuilder: (context, index) {
              if (index == 0) {
                return widget.onLoadOlder == null && !widget.loadingOlder
                    ? const SizedBox.shrink()
                    : Center(
                        child: TextButton(
                            onPressed: widget.loadingOlder
                                ? null
                                : () {
                                    _capture();
                                    widget.onLoadOlder?.call();
                                  },
                            child: Text(widget.loadingOlder
                                ? uiText(context, '正在加载…', 'Loading…')
                                : uiText(context, '加载更早的消息',
                                    'Load earlier messages'))));
              }
              final i = index - 1;
              final key = _items.putIfAbsent(widget.ids[i], () {
                final newKey = GlobalKey();
                _idByKey[newKey] = widget.ids[i];
                return newKey;
              });
              return KeyedSubtree(
                  key: key,
                  child: ConversationColumn(
                      child: Padding(
                          padding: EdgeInsets.only(
                              bottom: i < widget.ids.length - 1 ? 20 : 0),
                          child: widget.itemBuilder(context, i))));
            }),
        if (!widget.view.following)
          Positioned(
              right: 16,
              bottom: 12,
              child: FilledButton.tonalIcon(
                  onPressed: () {
                    _capturePending = false;
                    setState(() => widget.view.following = true);
                  },
                  icon: const LucideIcon('arrow-down', size: 16),
                  label: Text(uiText(context, '回到最新', 'Latest')))),
      ]),
    );
  }
}
