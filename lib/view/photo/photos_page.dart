import 'dart:io';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../models/entity/photo_entity.dart';
import '../../service/photo/photo_service.dart';
import '../widgets/ai_backdrop.dart';

class PhotosPage extends StatefulWidget {
  const PhotosPage({super.key});

  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> {
  static const int _pageSize = 90;

  final ScrollController _scrollController = ScrollController();
  final PhotoService _photoService = PhotoService();

  List<PhotoEntity> _photos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;

  Set<String> _selectedTags = {};
  DateTimeRange? _selectedRange;

  List<_TagCount>? _tagStatsCache;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _photoService.localDataVersion.addListener(_handleLocalDataChanged);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _photoService.localDataVersion.removeListener(_handleLocalDataChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleLocalDataChanged() {
    if (!mounted) {
      return;
    }
    _tagStatsCache = null;
    _loadFirstPage();
  }

  void _onScroll() {
    if (!_hasMore || _isLoading || _isLoadingMore) return;
    final position = _scrollController.position;
    if (position.pixels > position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoading = true;
      _hasMore = true;
      _offset = 0;
      _photos = [];
    });

    try {
      final items = await _queryPhotos(offset: 0, limit: _pageSize);
      final hydratedItems = await _refreshPhotoPaths(items);
      if (!mounted) return;
      setState(() {
        _photos = hydratedItems;
        _offset = hydratedItems.length;
        _hasMore = hydratedItems.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载失败: $e')));
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    try {
      final items = await _queryPhotos(offset: _offset, limit: _pageSize);
      final hydratedItems = await _refreshPhotoPaths(items);
      if (!mounted) return;
      setState(() {
        _photos = [..._photos, ...hydratedItems];
        _offset += hydratedItems.length;
        _hasMore = hydratedItems.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载失败: $e')));
    }
  }

  Future<List<PhotoEntity>> _queryPhotos({
    required int offset,
    required int limit,
  }) async {
    final isar = _photoService.isar;

    var query = isar.collection<PhotoEntity>().filter().idGreaterThan(
      0,
      include: true,
    );

    final range = _selectedRange;
    if (range != null) {
      final start = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      ).millisecondsSinceEpoch;
      final end = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
        999,
      ).millisecondsSinceEpoch;
      query = query.timestampBetween(start, end);
    }

    if (_selectedTags.isNotEmpty) {
      final tags = _selectedTags.toList()..sort();
      query = query.group((q) {
        var inner = q.aiTagsElementEqualTo(tags.first, caseSensitive: false);
        for (final tag in tags.skip(1)) {
          inner = inner.or().aiTagsElementEqualTo(tag, caseSensitive: false);
        }
        return inner;
      });
    }

    return query.sortByTimestampDesc().offset(offset).limit(limit).findAll();
  }

  Future<List<PhotoEntity>> _refreshPhotoPaths(List<PhotoEntity> photos) async {
    if (photos.isEmpty) {
      return photos;
    }

    final isar = _photoService.isar;
    final changed = <PhotoEntity>[];

    for (final photo in photos) {
      if (photo.path.isNotEmpty && File(photo.path).existsSync()) {
        continue;
      }

      final asset = await AssetEntity.fromId(photo.assetId);
      final file = await asset?.file;
      final latestPath = file?.path;
      if (latestPath == null ||
          latestPath.isEmpty ||
          latestPath == photo.path) {
        continue;
      }

      photo.path = latestPath;
      changed.add(photo);
    }

    if (changed.isNotEmpty) {
      await isar.writeTxn(() async {
        await isar.collection<PhotoEntity>().putAll(changed);
      });
    }

    return photos;
  }

  Future<List<_TagCount>> _loadTagStats() async {
    final cache = _tagStatsCache;
    if (cache != null) return cache;

    final isar = _photoService.isar;
    final tagLists = await isar
        .collection<PhotoEntity>()
        .filter()
        .aiTagsIsNotNull()
        .aiTagsProperty()
        .findAll();

    final counts = <String, int>{};
    for (final tags in tagLists) {
      if (tags == null) continue;
      for (final tag in tags) {
        if (tag.trim().isEmpty) continue;
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }

    final stats =
        counts.entries
            .map((e) => _TagCount(tag: e.key, count: e.value))
            .toList()
          ..sort((a, b) {
            final d = b.count.compareTo(a.count);
            if (d != 0) return d;
            return a.tag.compareTo(b.tag);
          });

    _tagStatsCache = stats;
    return stats;
  }

  Future<void> _openFilterSheet() async {
    final theme = Theme.of(context);

    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final media = MediaQuery.of(context);
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: AIPanel(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: _FilterSheet(
              theme: theme,
              initialSelectedTags: _selectedTags,
              initialRange: _selectedRange,
              loadTagStats: _loadTagStats,
            ),
          ),
        );
      },
    );

    if (!mounted || result == null) return;
    setState(() {
      _selectedTags = result.selectedTags;
      _selectedRange = result.range;
    });
    await _loadFirstPage();
  }

  void _clearAllFilters() {
    setState(() {
      _selectedTags = {};
      _selectedRange = null;
    });
    _loadFirstPage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white.withValues(alpha: 0.7),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('图片'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_rounded),
            tooltip: '筛选',
            onPressed: _openFilterSheet,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AIBackdrop(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            if (_selectedTags.isNotEmpty || _selectedRange != null)
              SliverToBoxAdapter(
                child: _ActivePhotoFiltersBar(
                  selectedTags: _selectedTags,
                  range: _selectedRange,
                  onClearAll: _clearAllFilters,
                  onRemoveTag: (tag) {
                    setState(() => _selectedTags.remove(tag));
                    _loadFirstPage();
                  },
                  onClearRange: () {
                    setState(() => _selectedRange = null);
                    _loadFirstPage();
                  },
                ),
              ),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_photos.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: AIPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
                    ),
                    child: Text(
                      _selectedTags.isEmpty && _selectedRange == null
                          ? '暂无图片，请先去「回忆」页扫描相册'
                          : '没有找到符合筛选条件的图片',
                      textAlign: TextAlign.center,
                      style: const TextStyle(height: 1.5),
                    ),
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final photo = _photos[index];
                    return _PhotoTile(
                      photo: photo,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _PhotoPreviewPage(photo: photo),
                          ),
                        );
                      },
                    );
                  }, childCount: _photos.length),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.86,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 120),
                  child: Center(
                    child: _isLoadingMore
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : (!_hasMore
                              ? Text(
                                  '已加载全部',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                )
                              : const SizedBox(height: 12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: (_selectedTags.isNotEmpty || _selectedRange != null)
          ? FloatingActionButton.extended(
              onPressed: _clearAllFilters,
              icon: const Icon(Icons.close_rounded),
              label: const Text(
                '清空筛选',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final PhotoEntity photo;
  final VoidCallback onTap;

  const _PhotoTile({required this.photo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
    final dateText = '${date.month}月${date.day}日';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(photo.path),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const ColoredBox(color: Color(0xFFE5E5EA)),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 72,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                bottom: 10,
                child: Text(
                  dateText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoPreviewPage extends StatefulWidget {
  final PhotoEntity photo;

  const _PhotoPreviewPage({required this.photo});

  @override
  State<_PhotoPreviewPage> createState() => _PhotoPreviewPageState();
}

class _PhotoPreviewPageState extends State<_PhotoPreviewPage> {
  final PhotoService _photoService = PhotoService();
  late PhotoEntity _photo;

  @override
  void initState() {
    super.initState();
    _photo = widget.photo;
    _photoService.localDataVersion.addListener(_handleLocalDataChanged);
    _reloadLatestPhoto();
  }

  @override
  void dispose() {
    _photoService.localDataVersion.removeListener(_handleLocalDataChanged);
    super.dispose();
  }

  void _handleLocalDataChanged() {
    _reloadLatestPhoto();
  }

  Future<void> _reloadLatestPhoto() async {
    final latest = await _photoService.isar.collection<PhotoEntity>().get(
      _photo.id,
    );
    if (!mounted || latest == null) {
      return;
    }
    setState(() {
      _photo = latest;
    });
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
    final title =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final file = File(photo.path);
    final fileExists = photo.path.isNotEmpty && file.existsSync();
    final fileName = photo.path.isEmpty ? '未知文件' : photo.path.split('/').last;
    final fileSizeText = fileExists ? _formatBytes(file.lengthSync()) : '文件不可用';
    final previewAspectRatio = photo.width > 0 && photo.height > 0
        ? photo.width / photo.height
        : 1.0;
    final dimensionsText = photo.width > 0 && photo.height > 0
        ? '${photo.width} × ${photo.height}'
        : '未知';
    final locationText = [
      photo.province,
      photo.city,
      photo.district,
    ].whereType<String>().where((item) => item.trim().isNotEmpty).join(' · ');
    final aiTags = photo.aiTags ?? const <String>[];

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1220),
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: previewAspectRatio > 0 ? previewAspectRatio : 1,
              child: ColoredBox(
                color: Colors.black,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Image.file(
                    File(photo.path),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Text(
                        '图片加载失败',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _PhotoInfoSection(
            title: '图片信息',
            items: [
              _PhotoInfoItem(
                label: '拍摄时间',
                value: '$title ${_formatTime(date)}',
              ),
              _PhotoInfoItem(label: '尺寸', value: dimensionsText),
              _PhotoInfoItem(label: '文件名', value: fileName),
              _PhotoInfoItem(label: '文件大小', value: fileSizeText),
              _PhotoInfoItem(
                label: 'Caption',
                value: (photo.caption?.trim().isNotEmpty ?? false)
                    ? photo.caption!.trim()
                    : '暂无描述',
              ),
              if (locationText.isNotEmpty)
                _PhotoInfoItem(label: '行政区', value: locationText),
              if (photo.formattedAddress?.isNotEmpty ?? false)
                _PhotoInfoItem(label: '详细地址', value: photo.formattedAddress!),
              _PhotoInfoItem(
                label: '分析状态',
                value: photo.isAiAnalyzed ? '已分析' : '未分析',
              ),
              _PhotoInfoItem(
                label: '标签',
                value: aiTags.isEmpty ? '暂无标签' : aiTags.join('、'),
              ),
              if (photo.isAiAnalyzed && photo.faceCount > 0)
                _PhotoInfoItem(label: '人脸数', value: '${photo.faceCount}'),
              if (photo.isAiAnalyzed && photo.smileProb > 0)
                _PhotoInfoItem(
                  label: '微笑概率',
                  value: '${(photo.smileProb * 100).toStringAsFixed(0)}%',
                ),
              if (photo.isAiAnalyzed && photo.joyScore != null)
                _PhotoInfoItem(
                  label: '欢乐值',
                  value: photo.joyScore!.toStringAsFixed(2),
                ),
              _PhotoInfoItem(
                label: '文件路径',
                value: photo.path.isEmpty ? '未知' : photo.path,
                isCollapsible: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _PhotoInfoSection extends StatelessWidget {
  final String title;
  final List<_PhotoInfoItem> items;

  const _PhotoInfoSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    items[i].label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: items[i].isCollapsible
                      ? _CollapsiblePhotoInfoValue(value: items[i].value)
                      : Text(
                          items[i].value,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                ),
              ],
            ),
            if (i != items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PhotoInfoItem {
  final String label;
  final String value;
  final bool isCollapsible;

  const _PhotoInfoItem({
    required this.label,
    required this.value,
    this.isCollapsible = false,
  });
}

class _CollapsiblePhotoInfoValue extends StatefulWidget {
  final String value;

  const _CollapsiblePhotoInfoValue({required this.value});

  @override
  State<_CollapsiblePhotoInfoValue> createState() =>
      _CollapsiblePhotoInfoValueState();
}

class _CollapsiblePhotoInfoValueState
    extends State<_CollapsiblePhotoInfoValue> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final canExpand = widget.value.length > 40;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.value,
          maxLines: _expanded || !canExpand ? null : 2,
          overflow: _expanded || !canExpand ? null : TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Color(0xFF0F172A),
          ),
        ),
        if (canExpand)
          GestureDetector(
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _expanded ? '收起' : '展开',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2563EB),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActivePhotoFiltersBar extends StatelessWidget {
  final Set<String> selectedTags;
  final DateTimeRange? range;
  final VoidCallback onClearAll;
  final ValueChanged<String> onRemoveTag;
  final VoidCallback onClearRange;

  const _ActivePhotoFiltersBar({
    required this.selectedTags,
    required this.range,
    required this.onClearAll,
    required this.onRemoveTag,
    required this.onClearRange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.92),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tag in selectedTags.toList()..sort())
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: tag,
                        onDeleted: () => onRemoveTag(tag),
                      ),
                    ),
                  if (range != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: _formatRange(range!),
                        onDeleted: onClearRange,
                      ),
                    ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: onClearAll,
            child: const Text(
              '清空',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatRange(DateTimeRange range) {
    final s = range.start;
    final e = range.end;
    return '${s.month}/${s.day}-${e.month}/${e.day}';
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onDeleted;

  const _FilterChip({required this.label, required this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E6FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onDeleted,
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final ThemeData theme;
  final Set<String> initialSelectedTags;
  final DateTimeRange? initialRange;
  final Future<List<_TagCount>> Function() loadTagStats;

  const _FilterSheet({
    required this.theme,
    required this.initialSelectedTags,
    required this.initialRange,
    required this.loadTagStats,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<String> _selectedTags;
  DateTimeRange? _range;

  String _tagQuery = '';
  List<_TagCount>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedTags = Set<String>.from(widget.initialSelectedTags);
    _range = widget.initialRange;
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await widget.loadTagStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载标签失败: $e')));
    }
  }

  void _clear() {
    setState(() {
      _selectedTags.clear();
      _range = null;
      _tagQuery = '';
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initial =
        _range ??
        DateTimeRange(
          start: DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 30)),
          end: DateTime(now.year, now.month, now.day),
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
      helpText: '选择时间范围',
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => _range = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final stats = _stats ?? const <_TagCount>[];
    final query = _tagQuery.trim();
    final filtered = query.isEmpty
        ? stats
        : stats
              .where((t) => t.tag.toLowerCase().contains(query.toLowerCase()))
              .toList();
    final top = stats.take(12).toList();

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
              child: Row(
                children: [
                  Text(
                    '筛选',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _clear,
                    child: const Text(
                      '清空',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _FilterResult(
                          selectedTags: Set<String>.from(_selectedTags),
                          range: _range,
                        ),
                      );
                    },
                    child: const Text(
                      '应用',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      children: [
                        TextField(
                          onChanged: (v) => setState(() => _tagQuery = v),
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText: '搜索标签',
                            hintStyle: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF94A3B8),
                            ),
                            prefixIcon: const Icon(
                              Icons.manage_search_rounded,
                              size: 20,
                              color: Color(0xFF64748B),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF1F5F9),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 0,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text(
                              '时间范围',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF334155),
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _pickRange,
                              child: Text(
                                _range == null ? '选择' : '修改',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_range != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_range!.start.year}/${_range!.start.month}/${_range!.start.day} - '
                                    '${_range!.end.year}/${_range!.end.month}/${_range!.end.day}',
                                    style: const TextStyle(
                                      color: Color(0xFF475569),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      setState(() => _range = null),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          '常用标签',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final item in top)
                              _SelectableTagChip(
                                tag: item.tag,
                                selected: _selectedTags.contains(item.tag),
                                onTap: () {
                                  setState(() {
                                    if (_selectedTags.contains(item.tag)) {
                                      _selectedTags.remove(item.tag);
                                    } else {
                                      _selectedTags.add(item.tag);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '全部标签',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...filtered.map((item) {
                          final selected = _selectedTags.contains(item.tag);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              item.tag,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text('${item.count}'),
                            trailing: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: selected
                                  ? theme.colorScheme.secondary
                                  : const Color(0xFF94A3B8),
                            ),
                            onTap: () {
                              setState(() {
                                if (selected) {
                                  _selectedTags.remove(item.tag);
                                } else {
                                  _selectedTags.add(item.tag);
                                }
                              });
                            },
                          );
                        }),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectableTagChip extends StatelessWidget {
  final String tag;
  final bool selected;
  final VoidCallback onTap;

  const _SelectableTagChip({
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.18),
                    theme.colorScheme.secondary.withValues(alpha: 0.12),
                  ],
                )
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.35)
                : const Color(0xFFD8E6FF),
          ),
        ),
        child: Text(
          tag,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected
                ? theme.colorScheme.primary
                : const Color(0xFF0F172A),
          ),
        ),
      ),
    );
  }
}

class _TagCount {
  final String tag;
  final int count;

  const _TagCount({required this.tag, required this.count});
}

class _FilterResult {
  final Set<String> selectedTags;
  final DateTimeRange? range;

  const _FilterResult({required this.selectedTags, required this.range});
}
