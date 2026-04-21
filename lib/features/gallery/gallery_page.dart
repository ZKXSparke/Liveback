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
import 'package:permission_handler/permission_handler.dart';

import '../../models/gallery_item.dart';
import '../../services/mediastore_channel.dart';
import '../../services/task_queue.dart';
import '../../widgets/mono_text.dart';
import '../../widgets/theme_access.dart';
import '../../widgets/thumbnail_cache.dart';

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

  // Permission state. `_permissionResolved` flips true once we've attempted
  // the request at least once; until then the UI shows a neutral loading
  // state rather than a "denied" / "empty" prompt (avoids a false flash).
  bool _permissionResolved = false;
  bool _permissionGranted = false;
  bool _permissionPermanentlyDenied = false;

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
    _scroll.addListener(_onScroll);
    unawaited(_requestPermissionAndLoad());
  }

  Future<void> _requestPermissionAndLoad({bool fromUserTap = false}) async {
    // `Permission.photos` is permission_handler's unified key: on Android 13+
    // it maps to READ_MEDIA_IMAGES; on API ≤32 it falls through to the
    // storage permission. On the first tap we use .request() which also
    // shows the system prompt if status is .denied.
    PermissionStatus status = await Permission.photos.status;
    if (status.isDenied || (fromUserTap && !status.isGranted)) {
      status = await Permission.photos.request();
    }
    if (!mounted) return;
    final granted = status.isGranted || status.isLimited;
    setState(() {
      _permissionResolved = true;
      _permissionGranted = granted;
      _permissionPermanentlyDenied = status.isPermanentlyDenied;
    });
    if (granted) {
      unawaited(_loadMore());
    }
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
                  child: _buildContent(),
                ),
              ),
            ),
            if (n > 0) _confirmBar(context, n),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Precedence: hard load error > unresolved / denied permission >
    // empty gallery > grid.
    if (_loadError != null) return _errorState();
    if (!_permissionResolved) return const _LoadingState();
    if (!_permissionGranted) {
      return _PermissionState(
        permanentlyDenied: _permissionPermanentlyDenied,
        onGrant: () {
          if (_permissionPermanentlyDenied) {
            openAppSettings();
          } else {
            _requestPermissionAndLoad(fromUserTap: true);
          }
        },
      );
    }
    if (_items.isEmpty && !_loading) return const _EmptyState();
    final scrollPhysics = _mode == _GestureMode.dragSelect
        ? const NeverScrollableScrollPhysics()
        : const AlwaysScrollableScrollPhysics();
    return GridView.builder(
      key: _gridKey,
      controller: _scroll,
      physics: scrollPhysics,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
              child: CircularProgressIndicator(strokeWidth: 2),
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
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = ThumbnailCache.instance.fetch(widget.item.contentUri);
  }

  @override
  void didUpdateWidget(covariant _ThumbnailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.contentUri != widget.item.contentUri) {
      _future = ThumbnailCache.instance.fetch(widget.item.contentUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // RepaintBoundary makes each tile its own compositor layer — scrolling
    // and selection animations on neighbors no longer re-rasterize this
    // tile's decoded bitmap.
    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Base image layer — rebuilds ONLY when the future resolves or
            // URI changes, not on every selection toggle.
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  color: c.panel,
                  child: FutureBuilder<Uint8List?>(
                    future: _future,
                    builder: (_, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        // Plain dim panel — no spinner per tile. Cheaper than
                        // CircularProgressIndicator × 120.
                        return const SizedBox.expand();
                      }
                      final bytes = snap.data;
                      if (bytes == null) {
                        return Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: c.inkFaint,
                            size: 22,
                          ),
                        );
                      }
                      // Only cacheWidth — Image.memory scales height
                      // preserving aspect. Setting BOTH triggers ResizeImage
                      // with default `policy: exact` which stretches to
                      // square and distorts non-1:1 photos. Width 400 keeps
                      // bitmap small (~600 KB/tile on landscape) while
                      // staying ≥ tile display size under BoxFit.cover.
                      return Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        cacheWidth: 400,
                      );
                    },
                  ),
                ),
              ),
            ),
            // Selection border + soft overlay — only this small layer
            // rebuilds when `widget.selected` flips.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: widget.selected ? c.accent : c.border,
                      width: widget.selected ? 2 : 1,
                    ),
                    color: widget.selected ? c.accentSoft : Colors.transparent,
                  ),
                ),
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

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(strokeWidth: 2, color: c.inkFaint),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.collections_outlined, size: 44, color: c.inkFaint),
            const SizedBox(height: 16),
            Text(
              '图库里没有图片',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.ink,
                letterSpacing: -0.15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '拍摄实况图或从相册导入后再来',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.inkDim, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionState extends StatelessWidget {
  final bool permanentlyDenied;
  final VoidCallback onGrant;

  const _PermissionState({
    required this.permanentlyDenied,
    required this.onGrant,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = permanentlyDenied ? '权限已关闭' : '需要图库访问权限';
    final body = permanentlyDenied
        ? '在系统设置里给 Liveback 开启"照片和视频"权限后再回到这里。'
        : '读取你相册里的实况图，才能送去修复。权限只用于本机解析，不上传。';
    final btn = permanentlyDenied ? '去系统设置' : '授予权限';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: c.inkFaint),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.ink,
                letterSpacing: -0.15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.inkDim, height: 1.5),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onGrant,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.bg,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(btn,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
