import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

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
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;

  List<PhotoEntity> _photos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;

  String _keyword = '';
  Set<String> _selectedTags = {};
  DateTimeRange? _selectedRange;

  List<_TagCount>? _tagStatsCache;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
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
      if (!mounted) return;
      setState(() {
        _photos = items;
        _offset = items.length;
        _hasMore = items.length == _pageSize;
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
      if (!mounted) return;
      setState(() {
        _photos = [..._photos, ...items];
        _offset += items.length;
        _hasMore = items.length == _pageSize;
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
    final isar = PhotoService().isar;

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

    final keyword = _keyword.trim();
    if (keyword.isNotEmpty) {
      query = query.aiTagsElementContains(keyword, caseSensitive: false);
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

  void _onKeywordChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _keyword = value);
      _loadFirstPage();
    });
  }

  Future<List<_TagCount>> _loadTagStats() async {
    final cache = _tagStatsCache;
    if (cache != null) return cache;

    final isar = PhotoService().isar;
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
    _searchController.clear();
    setState(() {
      _keyword = '';
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
            SliverPersistentHeader(
              pinned: true,
              delegate: _PhotoSearchHeaderDelegate(
                controller: _searchController,
                keyword: _keyword,
                selectedTags: _selectedTags,
                range: _selectedRange,
                onKeywordChanged: _onKeywordChanged,
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
                      _keyword.trim().isEmpty &&
                              _selectedTags.isEmpty &&
                              _selectedRange == null
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
      floatingActionButton:
          (_keyword.trim().isNotEmpty ||
              _selectedTags.isNotEmpty ||
              _selectedRange != null)
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
              if (photo.isAiAnalyzed)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: const Text(
                      'AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
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

class _PhotoPreviewPage extends StatelessWidget {
  final PhotoEntity photo;

  const _PhotoPreviewPage({required this.photo});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
    final title =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Image.file(
            File(photo.path),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Text('图片加载失败', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoSearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController controller;
  final String keyword;
  final Set<String> selectedTags;
  final DateTimeRange? range;
  final ValueChanged<String> onKeywordChanged;
  final VoidCallback onClearAll;
  final ValueChanged<String> onRemoveTag;
  final VoidCallback onClearRange;

  const _PhotoSearchHeaderDelegate({
    required this.controller,
    required this.keyword,
    required this.selectedTags,
    required this.range,
    required this.onKeywordChanged,
    required this.onClearAll,
    required this.onRemoveTag,
    required this.onClearRange,
  });

  @override
  double get minExtent => selectedTags.isEmpty && range == null ? 64 : 104;

  @override
  double get maxExtent => minExtent;

  @override
  bool shouldRebuild(_PhotoSearchHeaderDelegate oldDelegate) {
    return controller != oldDelegate.controller ||
        keyword != oldDelegate.keyword ||
        selectedTags.length != oldDelegate.selectedTags.length ||
        range != oldDelegate.range;
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final hasFilters = selectedTags.isNotEmpty || range != null;
    return Container(
      color: Colors.white.withValues(alpha: 0.92),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          TextField(
            controller: controller,
            onChanged: onKeywordChanged,
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              hintText: '搜索标签，例如：美食、海滩、猫…',
              hintStyle: const TextStyle(
                fontSize: 14,
                color: Color(0xFF94A3B8),
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 20,
                color: Color(0xFF64748B),
              ),
              suffixIcon: keyword.trim().isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Color(0xFF94A3B8),
                      ),
                      onPressed: () {
                        controller.clear();
                        onKeywordChanged('');
                      },
                    )
                  : null,
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
          if (hasFilters) ...[
            const SizedBox(height: 10),
            Row(
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
          ],
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
