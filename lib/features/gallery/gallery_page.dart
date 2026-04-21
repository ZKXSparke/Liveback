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
//
// Two UI additions overlay this (from kk/mp-detect-and-folders):
//   * Folder dropdown (Row 1 of the header) — opens a bottom sheet with
//     the album list (MediaStore BUCKET_ID). Default "全部相册" keeps the
//     current all-albums behaviour.
//   * Motion-Photo filter chip bar (Row 2) — "全部 | 仅显示实况图 | 待修复".
//     Pulls Motion-Photo probes per-tile and client-side filters the grid.
//
// Selection (`_selectedIds`) is stored by GalleryItem.id so it survives
// both filtering and paging — a selected tile that gets hidden by the
// filter is counted (+N indicator in the header) but not rendered.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/gallery_album.dart';
import '../../models/gallery_item.dart';
import '../../services/mediastore_channel.dart';
import '../../services/task_queue.dart';
import '../../widgets/mono_text.dart';
import '../../widgets/theme_access.dart';
import '../../widgets/thumbnail_cache.dart';
import '../preview/preview_page.dart';

const int _kMaxSelection = 100;
const int _kPageSize = 120;

/// Max consecutive auto-loads when a filter is hiding most of the page.
/// Bounds the worst case where every loaded image is a non-Motion Photo.
const int _kMaxAutoLoadRounds = 3;

enum _GalleryFilter {
  all,
  motionOnly,
  needsFix,
}

/// Pure filter predicate exercised by unit tests via `debugGalleryTilePasses`.
/// Tiles with unresolved probes (`probe == null`) always pass so that
/// scrolling doesn't flicker them in and out while probes resolve.
bool _tilePasses(_GalleryFilter filter, MotionPhotoProbe? probe) {
  if (filter == _GalleryFilter.all) return true;
  if (probe == null) return true;
  switch (filter) {
    case _GalleryFilter.all:
      return true;
    case _GalleryFilter.motionOnly:
      return probe.isMotionPhoto;
    case _GalleryFilter.needsFix:
      return probe.isMotionPhoto && !probe.isSamsungNative;
  }
}

/// Testing hook. Exposes [_tilePasses] + filter enum to unit tests without
/// exporting the private widget state.
///
/// Usage: `debugGalleryTilePasses('all', probe)` etc.
@visibleForTesting
bool debugGalleryTilePasses(String filterName, MotionPhotoProbe? probe) {
  final f = switch (filterName) {
    'all' => _GalleryFilter.all,
    'motionOnly' => _GalleryFilter.motionOnly,
    'needsFix' => _GalleryFilter.needsFix,
    _ => throw ArgumentError('unknown filter: $filterName'),
  };
  return _tilePasses(f, probe);
}

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final MediaStoreChannel _channel = MediaStoreChannel();
  // Master list: everything queryImages has returned so far (in DATE_TAKEN
  // DESC order). Filtering is applied as a view over this list.
  final List<GalleryItem> _items = [];
  // Resolved probes keyed by GalleryItem.id. Tiles kick off their probe
  // in initState and call back with the resolved value, so the parent can
  // recompute the filtered view without re-probing.
  final Map<int, MotionPhotoProbe> _probes = {};
  // Selected GalleryItem.ids — stable across filter changes and paging.
  final Set<int> _selectedIds = {};
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

  // Albums / bucket picker state.
  List<GalleryAlbum> _albums = const [];
  bool _albumsLoading = false;
  int? _selectedBucketId; // null ⇒ "all albums"
  String? _selectedBucketLabel; // cached for header render

  // Motion-Photo filter chip state.
  _GalleryFilter _filter = _GalleryFilter.all;

  // Gesture state machine (§11). Indices are into the CURRENTLY VISIBLE
  // list — gestures only target visible tiles; filtered-out rows are not
  // reachable via hit-test.
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
      unawaited(_loadAlbums());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore({int autoRound = 0}) async {
    if (_loading || _reachedEnd) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final next = await _channel.queryImages(
        limit: _kPageSize,
        offset: _items.length,
        bucketId: _selectedBucketId,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(next);
        _reachedEnd = next.length < _kPageSize;
        _loading = false;
      });
      // If the filter is hiding most tiles on this page, auto-advance up
      // to _kMaxAutoLoadRounds pages before surfacing "no more" to the
      // user. Prevents the grid from looking empty when e.g. "待修复" only
      // matches a handful of photos in a 120-image batch.
      if (!_reachedEnd &&
          _filter != _GalleryFilter.all &&
          autoRound < _kMaxAutoLoadRounds &&
          _visibleItems().length < 12) {
        await _loadMore(autoRound: autoRound + 1);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadAlbums() async {
    if (_albumsLoading) return;
    setState(() => _albumsLoading = true);
    try {
      final albums = await _channel.queryAlbums();
      if (!mounted) return;
      setState(() {
        _albums = albums;
        _albumsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _albumsLoading = false);
      // Non-fatal — bottom sheet will show the empty placeholder.
    }
  }

  void _onSelectBucket(GalleryAlbum? album) {
    // null album ⇒ "all albums".
    final newBucketId = album?.bucketId;
    if (newBucketId == _selectedBucketId) return;
    setState(() {
      _selectedBucketId = newBucketId;
      _selectedBucketLabel = album?.displayName;
      _items.clear();
      _reachedEnd = false;
      _loadError = null;
      // Probes and selections are stable across bucket switches (they key
      // on item.id / contentUri, not position). Do NOT clear them.
    });
    _loadMore();
  }

  void _onSelectFilter(_GalleryFilter f) {
    if (f == _filter) return;
    setState(() => _filter = f);
    // Reset gesture state — any in-flight drag-select would otherwise be
    // operating against a now-stale visible index mapping.
    _touchedThisGesture.clear();
    _anchorIndex = null;
    _lastTouchedIndex = null;
    _mode = _GestureMode.idle;
    // Auto-advance pagination if the new filter hides most loaded tiles.
    if (!_reachedEnd && _visibleItems().length < 12) {
      _loadMore();
    }
  }

  // ---------------------------------------------------------------------
  // Filter view
  // ---------------------------------------------------------------------

  /// Derives the list of items that should be rendered right now. Tiles
  /// whose probe hasn't resolved yet stay visible under any filter so
  /// scrolling doesn't flicker them in and out.
  List<GalleryItem> _visibleItems() {
    if (_filter == _GalleryFilter.all) return _items;
    return _items
        .where((it) => _tilePasses(_filter, _probes[it.id]))
        .toList(growable: false);
  }

  void _onTileProbeResolved(GalleryItem item, MotionPhotoProbe p) {
    if (!mounted) return;
    final prev = _probes[item.id];
    _probes[item.id] = p;
    // Only rebuild when the probe meaningfully changed AND a filter is
    // active — saves setState churn during fast scroll under the default
    // "all" filter.
    if (prev != p && _filter != _GalleryFilter.all) {
      setState(() {});
      // If the filter just hid this tile and the grid is now underfull,
      // pull another page in.
      if (!_reachedEnd && _visibleItems().length < 12) {
        _loadMore();
      }
    }
  }

  // ---------------------------------------------------------------------
  // Selection (by GalleryItem.id)
  // ---------------------------------------------------------------------

  void _toggleById(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else if (_selectedIds.length < _kMaxSelection) {
        _selectedIds.add(id);
      }
    });
  }

  void _openPreview(GalleryItem item) {
    Navigator.of(context).pushNamed(
      '/preview',
      arguments: PreviewPageArgs(
        contentUri: item.contentUri,
        displayName: item.displayName,
        sizeBytes: item.size,
      ),
    );
  }

  /// Drag-select "apply" — driven by the gesture state machine. Operates
  /// on ids of the currently-visible items at each touched index.
  void _applyTargetByVisibleIndex(int visibleIndex) {
    final visible = _visibleItems();
    if (visibleIndex < 0 || visibleIndex >= visible.length) return;
    final id = visible[visibleIndex].id;
    if (_anchorTargetSelect) {
      if (_selectedIds.length >= _kMaxSelection &&
          !_selectedIds.contains(id)) {
        return;
      }
      _selectedIds.add(id);
    } else {
      _selectedIds.remove(id);
    }
  }

  // ---------------------------------------------------------------------
  // Gesture state machine (§11) — indices are over _visibleItems().
  // ---------------------------------------------------------------------

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
    final visible = _visibleItems();
    if (anchor < 0 || anchor >= visible.length) return;
    final anchorId = visible[anchor].id;
    setState(() {
      _mode = _GestureMode.dragSelect;
      _anchorIndex = anchor;
      _anchorTargetSelect = !_selectedIds.contains(anchorId);
      _touchedThisGesture
        ..clear()
        ..add(anchor);
      _applyTargetByVisibleIndex(anchor);
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
          _applyTargetByVisibleIndex(i);
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
    final visible = _visibleItems();
    if (idx < 0 || idx >= visible.length) return null;
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
    if (_selectedIds.isEmpty) return;
    final byId = {for (final it in _items) it.id: it};
    final inputs = <TaskQueueInput>[];
    for (final id in _selectedIds) {
      final it = byId[id];
      if (it == null) continue;
      inputs.add(
        TaskQueueInput(
          id: 'task-${DateTime.now().microsecondsSinceEpoch}-${it.id}',
          contentUri: it.contentUri,
          displayName: it.displayName,
          sizeBytes: it.size,
        ),
      );
    }
    if (inputs.isEmpty) return;
    await TaskQueue.instance.enqueueAll(inputs);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/tasks');
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = _selectedIds.length;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context, n),
            if (_permissionGranted) _filterBar(context),
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
    final visible = _visibleItems();
    if (visible.isEmpty && !_loading) {
      // Distinguish "truly empty" (no images in selection at all) from
      // "filtered empty" (images exist but none match the current filter).
      if (_items.isEmpty && _filter == _GalleryFilter.all) {
        return const _EmptyState();
      }
      if (_reachedEnd) {
        return _FilteredEmptyState(filter: _filter);
      }
      // Still loading more and nothing visible yet — fall through to the
      // grid which will render only the trailing loader.
    }
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
      itemCount: visible.length + (_loading || !_reachedEnd ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i >= visible.length) {
          if (_reachedEnd) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: MonoText(
                  _filter == _GalleryFilter.all
                      ? '没有更多图片了'
                      : '没有更多符合条件的图片',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.inkFaint,
                  ),
                ),
              ),
            );
          }
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final item = visible[i];
        final selected = _selectedIds.contains(item.id);
        return _ThumbnailTile(
          key: ValueKey(item.id),
          item: item,
          selected: selected,
          probe: _probes[item.id],
          onTap: () => _openPreview(item),
          onCheckboxTap: () => _toggleById(item.id),
          onProbeResolved: (p) => _onTileProbeResolved(item, p),
        );
      },
    );
  }

  Widget _header(BuildContext context, int n) {
    final c = context.colors;
    final bucketLabel = _selectedBucketLabel ?? '全部相册';
    final visible = _visibleItems();
    final hiddenSelected = n -
        _selectedIds.where((id) => visible.any((it) => it.id == id)).length;
    final selectionLabel = hiddenSelected > 0
        ? '$n/$_kMaxSelection · +$hiddenSelected 张已选但隐藏'
        : '$n/$_kMaxSelection';
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 2),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back_ios_new, color: c.ink, size: 20),
            splashRadius: 22,
          ),
          Expanded(
            child: InkWell(
              onTap: _permissionGranted ? _openAlbumPicker : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        _permissionGranted ? bucketLabel : '选择实况图',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                          letterSpacing: -0.17,
                        ),
                      ),
                    ),
                    if (_permissionGranted) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down,
                          color: c.inkDim, size: 20),
                    ],
                  ],
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: n == 0 ? null : _confirm,
            style: TextButton.styleFrom(
              foregroundColor: c.accent,
              disabledForegroundColor: c.inkFaint,
            ),
            child: Text(
              '完成 · $selectionLabel',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Row(
        children: [
          _FilterChip(
            label: '全部',
            selected: _filter == _GalleryFilter.all,
            onTap: () => _onSelectFilter(_GalleryFilter.all),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: '仅显示实况图',
            selected: _filter == _GalleryFilter.motionOnly,
            onTap: () => _onSelectFilter(_GalleryFilter.motionOnly),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: '待修复',
            selected: _filter == _GalleryFilter.needsFix,
            onTap: () => _onSelectFilter(_GalleryFilter.needsFix),
          ),
          const Spacer(),
          if (_loading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: c.inkFaint,
              ),
            ),
        ],
      ),
    );
  }

  void _openAlbumPicker() async {
    final picked = await showModalBottomSheet<_AlbumPickerResult>(
      context: context,
      backgroundColor: context.colors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _AlbumPickerSheet(
        albums: _albums,
        loading: _albumsLoading,
        selectedBucketId: _selectedBucketId,
      ),
    );
    if (picked == null) return;
    _onSelectBucket(picked.album);
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.accent : c.panel,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : c.inkDim,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Result of the bottom-sheet picker. Null `album` → "全部相册".
class _AlbumPickerResult {
  final GalleryAlbum? album;
  const _AlbumPickerResult(this.album);
}

class _AlbumPickerSheet extends StatelessWidget {
  final List<GalleryAlbum> albums;
  final bool loading;
  final int? selectedBucketId;

  const _AlbumPickerSheet({
    required this.albums,
    required this.loading,
    required this.selectedBucketId,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FractionallySizedBox(
      heightFactor: 0.7,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: 36,
                height: 3,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text(
              '选择相册',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _body(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    if (loading && albums.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (albums.isEmpty) {
      return Center(
        child: MonoText(
          '图库里没有相册',
          style: TextStyle(fontSize: 12, color: c.inkDim),
        ),
      );
    }
    return ListView.separated(
      itemCount: albums.length + 1,
      separatorBuilder: (ctx, i) => Divider(
        color: c.border,
        height: 1,
      ),
      itemBuilder: (ctx, i) {
        if (i == 0) {
          final allSelected = selectedBucketId == null;
          return _AlbumRow(
            album: null,
            label: '全部相册',
            subtitle: null,
            selected: allSelected,
            onTap: () =>
                Navigator.of(ctx).pop(const _AlbumPickerResult(null)),
          );
        }
        final album = albums[i - 1];
        final selected = selectedBucketId == album.bucketId;
        return _AlbumRow(
          album: album,
          label: album.displayName,
          subtitle: '${album.count} 张',
          selected: selected,
          onTap: () => Navigator.of(ctx).pop(_AlbumPickerResult(album)),
        );
      },
    );
  }
}

class _AlbumRow extends StatefulWidget {
  final GalleryAlbum? album;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _AlbumRow({
    required this.album,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_AlbumRow> createState() => _AlbumRowState();
}

class _AlbumRowState extends State<_AlbumRow> {
  Uint8List? _cover;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  Future<void> _loadCover() async {
    final uri = widget.album?.coverContentUri;
    if (uri == null) return;
    try {
      final bytes = await ThumbnailCache.instance.fetch(uri);
      if (!mounted) return;
      setState(() => _cover = bytes);
    } catch (_) {
      // leave empty — row shows the placeholder icon.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border, width: 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: _cover != null
                  ? Image.memory(_cover!,
                      fit: BoxFit.cover, gaplessPlayback: true)
                  : Icon(
                      widget.album == null
                          ? Icons.photo_library_outlined
                          : Icons.folder_outlined,
                      color: c.inkFaint,
                      size: 20,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.ink,
                    ),
                  ),
                  if (widget.subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: MonoText(
                        widget.subtitle!,
                        style: TextStyle(fontSize: 11, color: c.inkFaint),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.selected)
              Icon(Icons.check, color: c.accent, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailTile extends StatefulWidget {
  final GalleryItem item;
  final bool selected;

  /// Body tap — fires when the user taps anywhere on the tile except the
  /// checkmark chip. Wired to open the preview page.
  final VoidCallback onTap;

  /// Checkbox tap — fires when the user taps the ~20 dp checkmark chip in
  /// the top-right corner. Wired to toggle selection.
  final VoidCallback onCheckboxTap;

  /// If the parent has already resolved a probe for this URI (cache hit),
  /// pass it in to skip the probe call entirely.
  final MotionPhotoProbe? probe;

  /// Notified the first time the tile resolves its own probe. Parent uses
  /// this to drive filter-chip visibility + client-side filtering.
  final void Function(MotionPhotoProbe)? onProbeResolved;

  const _ThumbnailTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onCheckboxTap,
    this.probe,
    this.onProbeResolved,
  });

  @override
  State<_ThumbnailTile> createState() => _ThumbnailTileState();
}

class _ThumbnailTileState extends State<_ThumbnailTile> {
  late Future<Uint8List?> _future;

  // Probe runs in parallel with the thumbnail load; result fed through
  // `widget.probe` or resolved here directly if the parent didn't supply
  // one. Resolved → rebuild to paint the badge.
  MotionPhotoProbe? _probe;

  @override
  void initState() {
    super.initState();
    _future = ThumbnailCache.instance.fetch(widget.item.contentUri);
    _probe = widget.probe;
    _probeIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _ThumbnailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.contentUri != widget.item.contentUri) {
      _future = ThumbnailCache.instance.fetch(widget.item.contentUri);
    }
    // If parent passes a resolved probe after the fact, adopt it.
    if (widget.probe != null && widget.probe != _probe) {
      _probe = widget.probe;
    }
  }

  Future<void> _probeIfNeeded() async {
    if (widget.probe != null) {
      _probe = widget.probe;
      return;
    }
    try {
      final p = await MediaStoreChannel()
          .probeMotionPhoto(widget.item.contentUri);
      if (!mounted) return;
      setState(() {
        _probe = p;
      });
      widget.onProbeResolved?.call(p);
    } catch (_) {
      // Any error → no badge; leave _probe null.
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
                    color:
                        widget.selected ? c.accentSoft : Colors.transparent,
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
            // Motion-photo badge — painted only when the probe resolved
            // and the file is a Motion Photo. Top-left so it does not
            // overlap the top-right selection chip.
            if (_probe != null && _probe!.isMotionPhoto)
              Positioned(
                left: 6,
                top: 6,
                child: _MotionBadge(probe: _probe!),
              ),
            Positioned(
              right: 6,
              top: 6,
              // Absorb tap so it targets selection toggle instead of the
              // outer body tap (which opens preview). Slight extra padding
              // widens the 20 dp chip's hit area without resizing the visual.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onCheckboxTap,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _Checkmark(selected: widget.selected),
                ),
              ),
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

/// Small corner badge painted on tiles whose probe resolved to a Motion
/// Photo. Two flavours:
///   * already Samsung-native → subtle green dot + "已是三星" (informational —
///     user can see at a glance this file doesn't need processing)
///   * djimimo / other non-native → orange dot + "待修复"
class _MotionBadge extends StatelessWidget {
  final MotionPhotoProbe probe;
  const _MotionBadge({required this.probe});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isNative = probe.isSamsungNative;
    final dotColor = isNative ? c.success : c.warn;
    final label = isNative ? '已是三星' : '待修复';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              color: Colors.white,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
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

/// Shown when there are images loaded but none match the current filter or
/// selected bucket. Distinct from [_EmptyState] so the user knows changing
/// the filter/bucket will bring tiles back.
class _FilteredEmptyState extends StatelessWidget {
  final _GalleryFilter filter;
  const _FilteredEmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = switch (filter) {
      _GalleryFilter.all => '这个相册里没有图片',
      _GalleryFilter.motionOnly => '没有符合条件的实况图',
      _GalleryFilter.needsFix => '没有待修复的实况图',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_alt_outlined, size: 36, color: c.inkFaint),
            const SizedBox(height: 12),
            MonoText(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: c.inkDim),
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
