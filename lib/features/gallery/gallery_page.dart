// Owner: T3 (UI teammate). Reference: Doc 1 §5.3.2 + §11 (swipe-select
// state machine) + JSX design-v2/project/components/gallery.jsx.
//
// MediaStore-backed grid with pagination, cached thumbnails (LRU), and
// a three-finger / long-press drag-select gesture that matches the §11
// algorithm literally (anchorState, cross-axis cancel, scroll suppression).
//
// Pagination: first page = 120 items; loadMore fires when the scroll
// position enters the last quarter of the loaded range. Cap 100 images
// per brand §6.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/gallery_item.dart';
import '../../services/mediastore_channel.dart';
import '../../services/task_queue.dart';
import '../../widgets/mono_text.dart';
import '../../widgets/theme_access.dart';

const int _kMaxSelection = 100;
const int _kPageSize = 120;

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final MediaStoreChannel _channel = MediaStoreChannel();
  final List<GalleryItem> _items = [];
  final Set<int> _selected = {};
  final ScrollController _scroll = ScrollController();

  bool _loading = false;
  bool _reachedEnd = false;
  String? _loadError;

  // Gesture state machine (§11).
  final GlobalKey _gridKey = GlobalKey();
  _GestureMode _mode = _GestureMode.idle;
  int? _anchorIndex;
  bool _anchorTargetSelect = true;
  int? _lastTouchedIndex;
  final Set<int> _touchedThisGesture = {};
  Offset? _pointerStart;

  @override
  void initState() {
    super.initState();
    _loadMore();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _reachedEnd) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final next = await _channel.queryImages(
        limit: _kPageSize,
        offset: _items.length,
      );
      setState(() {
        _items.addAll(next);
        _reachedEnd = next.length < _kPageSize;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  void _toggle(int index) {
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else if (_selected.length < _kMaxSelection) {
        _selected.add(index);
      }
    });
  }

  void _applyTargetState(int index) {
    if (_anchorTargetSelect) {
      if (_selected.length >= _kMaxSelection && !_selected.contains(index)) {
        return;
      }
      _selected.add(index);
    } else {
      _selected.remove(index);
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointerStart = e.localPosition;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_mode == _GestureMode.idle && _pointerStart != null) {
      final dx = e.localPosition.dx - _pointerStart!.dx;
      final dy = e.localPosition.dy - _pointerStart!.dy;
      if (dx.abs() + dy.abs() < 8) return;
      if (dx.abs() > dy.abs() * 1.5) {
        // Promote to DRAG_SELECT at the initial cell.
        final idx = _hitTest(_pointerStart!);
        if (idx != null) {
          _beginDragSelect(idx);
        }
      } else {
        _mode = _GestureMode.scroll;
      }
    }
    if (_mode == _GestureMode.dragSelect) {
      final idx = _hitTest(e.localPosition);
      if (idx == null) return;
      _extendDragSelect(idx);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    setState(() {
      _mode = _GestureMode.idle;
      _anchorIndex = null;
      _lastTouchedIndex = null;
      _touchedThisGesture.clear();
      _pointerStart = null;
    });
  }

  void _beginDragSelect(int anchor) {
    setState(() {
      _mode = _GestureMode.dragSelect;
      _anchorIndex = anchor;
      _anchorTargetSelect = !_selected.contains(anchor);
      _touchedThisGesture
        ..clear()
        ..add(anchor);
      _applyTargetState(anchor);
      _lastTouchedIndex = anchor;
    });
  }

  void _extendDragSelect(int ic) {
    if (ic == _lastTouchedIndex) return;
    setState(() {
      final last = _lastTouchedIndex ?? _anchorIndex!;
      final lo = last < ic ? last : ic;
      final hi = last > ic ? last : ic;
      for (var i = lo; i <= hi; i++) {
        if (!_touchedThisGesture.contains(i)) {
          _applyTargetState(i);
          _touchedThisGesture.add(i);
        }
      }
      _lastTouchedIndex = ic;
    });
  }

  int? _hitTest(Offset localPosition) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final globalPosition = box.localToGlobal(localPosition);
    final localInGrid = box.globalToLocal(globalPosition);
    final width = box.size.width;
    final cellSize = width / 3;
    final col = (localInGrid.dx / cellSize).floor().clamp(0, 2);
    if (!_scroll.hasClients) return null;
    final row = ((localInGrid.dy + _scroll.offset) / cellSize).floor();
    final idx = row * 3 + col;
    if (idx < 0 || idx >= _items.length) return null;
    return idx;
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final idx = _hitTest(details.localPosition);
    if (idx == null) return;
    _beginDragSelect(idx);
  }

  void _onLongPressMove(LongPressMoveUpdateDetails details) {
    if (_mode != _GestureMode.dragSelect) return;
    final idx = _hitTest(details.localPosition);
    if (idx == null) return;
    _extendDragSelect(idx);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    setState(() {
      _mode = _GestureMode.idle;
      _anchorIndex = null;
      _lastTouchedIndex = null;
      _touchedThisGesture.clear();
    });
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty) return;
    final inputs = <TaskQueueInput>[];
    for (final i in _selected) {
      final it = _items[i];
      inputs.add(
        TaskQueueInput(
          id: 'task-${DateTime.now().microsecondsSinceEpoch}-${it.id}',
          contentUri: it.contentUri,
          displayName: it.displayName,
          sizeBytes: it.size,
        ),
      );
    }
    await TaskQueue.instance.enqueueAll(inputs);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/tasks');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = _selected.length;
    final scrollPhysics = _mode == _GestureMode.dragSelect
        ? const NeverScrollableScrollPhysics()
        : const AlwaysScrollableScrollPhysics();

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context, n),
            Expanded(
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                child: GestureDetector(
                  onLongPressStart: _onLongPressStart,
                  onLongPressMoveUpdate: _onLongPressMove,
                  onLongPressEnd: _onLongPressEnd,
                  child: _loadError != null
                      ? _errorState()
                      : GridView.builder(
                          key: _gridKey,
                          controller: _scroll,
                          physics: scrollPhysics,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                            childAspectRatio: 1,
                          ),
                          itemCount: _items.length + (_loading ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i >= _items.length) {
                              return const Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              );
                            }
                            final item = _items[i];
                            final selected = _selected.contains(i);
                            return _ThumbnailTile(
                              key: ValueKey(item.id),
                              item: item,
                              selected: selected,
                              onTap: () => _toggle(i),
                            );
                          },
                        ),
                ),
              ),
            ),
            if (n > 0) _confirmBar(context, n),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, int n) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back_ios_new, color: c.ink, size: 20),
            splashRadius: 22,
          ),
          Expanded(
            child: Text(
              '选择实况图 · $n/$_kMaxSelection',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.ink,
                letterSpacing: -0.17,
              ),
            ),
          ),
          TextButton(
            onPressed: n == 0 ? null : _confirm,
            style: TextButton.styleFrom(
              foregroundColor: c.accent,
              disabledForegroundColor: c.inkFaint,
            ),
            child: const Text(
              '完成',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmBar(BuildContext context, int n) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.border, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$n 张实况图 · 开始修复',
              style: TextStyle(fontSize: 14, color: c.ink),
            ),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.inkDim,
              side: BorderSide(color: c.borderStrong, width: 1),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('取消'),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('开始修复'),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined, size: 36, color: c.inkDim),
            const SizedBox(height: 12),
            MonoText(
              '图库读取失败\n$_loadError',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: c.inkDim),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadMore,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailTile extends StatefulWidget {
  final GalleryItem item;
  final bool selected;
  final VoidCallback onTap;

  const _ThumbnailTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ThumbnailTile> createState() => _ThumbnailTileState();
}

class _ThumbnailTileState extends State<_ThumbnailTile> {
  static final Map<String, Uint8List?> _cache = {};
  Uint8List? _bytes;
  bool _loading = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_cache.containsKey(widget.item.contentUri)) {
      setState(() {
        _bytes = _cache[widget.item.contentUri];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final b = await MediaStoreChannel()
          .getThumbnail(widget.item.contentUri, maxDim: 256);
      _cache[widget.item.contentUri] = b;
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: widget.selected ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: widget.selected ? c.accent : c.border,
                  width: widget.selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _thumbInner(c),
            ),
            if (widget.selected)
              Container(
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            Positioned(
              left: 6,
              bottom: 5,
              child: MonoText(
                _formatSize(widget.item.size),
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  letterSpacing: 0.2,
                  shadows: [
                    Shadow(
                      color: Color(0x99000000),
                      offset: Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: _Checkmark(selected: widget.selected),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbInner(LivebackColors c) {
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true);
    }
    if (_error) {
      return Container(
        color: c.border,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined, color: c.inkFaint, size: 22),
      );
    }
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: c.inkFaint,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _Checkmark extends StatelessWidget {
  final bool selected;
  const _Checkmark({required this.selected});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.accent : const Color(0x40000000),
        border: selected
            ? null
            : Border.all(color: const Color(0xD9FFFFFF), width: 1.5),
      ),
      child: selected
          ? const Icon(Icons.check, color: Colors.white, size: 12)
          : const SizedBox.shrink(),
    );
  }
}

String _formatSize(int bytes) {
  if (bytes >= 1 << 20) {
    return '${(bytes / (1 << 20)).toStringAsFixed(2)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}

enum _GestureMode { idle, dragSelect, scroll }
