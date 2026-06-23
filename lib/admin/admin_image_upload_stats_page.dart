import 'package:calscan/admin/nutrition_library_admin_page.dart';
import 'package:calscan/logic/admin_food_library_service.dart';
import 'package:calscan/logic/food_lookup_service.dart';
import 'package:flutter/material.dart';

const _kOrange = Color(0xFFFF7E00);
const _kBlue = Color(0xFF2563EB);
const _kGreen = Color(0xFF059669);

class AdminImageUploadStatsPage extends StatefulWidget {
  const AdminImageUploadStatsPage({super.key});

  @override
  State<AdminImageUploadStatsPage> createState() =>
      _AdminImageUploadStatsPageState();
}

class _AdminImageUploadStatsPageState extends State<AdminImageUploadStatsPage> {
  final FoodLookupService _lookup = FoodLookupService();
  final AdminFoodLibraryService _admin = AdminFoodLibraryService();

  late Future<_ImageUploadStats> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadStats();
  }

  Future<_ImageUploadStats> _loadStats() async {
    await _lookup.refreshRemoteEntries();
    final remote = await _admin.fetchAdminFoods();
    final bundled = {for (final food in _lookup.bundledEntries) food.key: food};
    final keys = <String>{...bundled.keys, ...remote.keys}.toList()..sort();

    final rows = [
      for (final key in keys)
        _ImageUploadRow(
          entry: remote[key] ?? bundled[key]!,
          hasAdminEntry: remote.containsKey(key),
        ),
    ]..sort((a, b) => a.entry.displayName.compareTo(b.entry.displayName));

    return _ImageUploadStats(rows);
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadStats());
    await _future;
  }

  void _openLibrary() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NutritionLibraryAdminPage()),
    ).then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: const Text('Image Upload Stats'),
        actions: [
          IconButton(
            tooltip: 'Refresh stats',
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_ImageUploadStats>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _kBlue),
            );
          }
          if (snapshot.hasError) {
            return _StatsErrorState(
              message: '${snapshot.error}',
              onRetry: _refresh,
            );
          }

          final stats = snapshot.data ?? const _ImageUploadStats([]);
          return RefreshIndicator(
            color: _kBlue,
            onRefresh: _refresh,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                28 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                _HeaderCard(stats: stats, onOpenLibrary: _openLibrary),
                const SizedBox(height: 14),
                _StatsGrid(stats: stats),
                const SizedBox(height: 14),
                _FirebaseReviewCard(theme: theme),
                const SizedBox(height: 14),
                _MissingImagesCard(stats: stats, onOpenLibrary: _openLibrary),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final _ImageUploadStats stats;
  final VoidCallback onOpenLibrary;

  const _HeaderCard({required this.stats, required this.onOpenLibrary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _kBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.image_search_rounded, color: _kBlue),
          ),
          const SizedBox(height: 14),
          Text(
            'Food image coverage',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This page shows numbers only. Admin can review actual uploaded files from Firebase Storage when needed.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onOpenLibrary,
            style: FilledButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.restaurant_menu_rounded),
            label: Text(
              stats.missingActive == 0
                  ? 'Open Food Library'
                  : 'Upload Missing Images',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final _ImageUploadStats stats;

  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _StatCard(
            color: _kBlue,
            icon: Icons.restaurant_rounded,
            value: stats.total.toString(),
            label: 'Total foods',
          ),
          _StatCard(
            color: _kGreen,
            icon: Icons.image_rounded,
            value: stats.withImages.toString(),
            label: 'With image',
          ),
          _StatCard(
            color: _kOrange,
            icon: Icons.cloud_done_rounded,
            value: stats.firebaseUploads.toString(),
            label: 'Firebase uploads',
          ),
          _StatCard(
            color: Colors.red,
            icon: Icons.image_not_supported_outlined,
            value: stats.missingActive.toString(),
            label: 'Missing active',
          ),
        ];

        if (constraints.maxWidth < 420) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i += 2) ...[
                Row(
                  children: [
                    Expanded(child: cards[i]),
                    const SizedBox(width: 10),
                    Expanded(child: cards[i + 1]),
                  ],
                ),
                if (i < cards.length - 2) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i != cards.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String value;
  final String label;

  const _StatCard({
    required this.color,
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FirebaseReviewCard extends StatelessWidget {
  final ThemeData theme;

  const _FirebaseReviewCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kGreen.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_queue_rounded, color: _kGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Uploaded food images are stored in Firebase Storage under food_images. The app only keeps the download URL and shows image counts here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingImagesCard extends StatelessWidget {
  final _ImageUploadStats stats;
  final VoidCallback onOpenLibrary;

  const _MissingImagesCard({required this.stats, required this.onOpenLibrary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = stats.missingRows.take(8).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.image_not_supported_outlined, color: _kOrange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Missing active images',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (missing.isEmpty)
            Text(
              'All active foods have an image URL.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            for (final row in missing) _MissingImageLine(row: row),
            if (stats.missingRows.length > missing.length) ...[
              const SizedBox(height: 8),
              Text(
                '+${stats.missingRows.length - missing.length} more',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onOpenLibrary,
              icon: const Icon(Icons.upload_rounded),
              label: const Text('Open Food Library'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MissingImageLine extends StatelessWidget {
  final _ImageUploadRow row;

  const _MissingImageLine({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _kOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.restaurant_menu_rounded,
              color: _kOrange,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (row.hasAdminEntry)
            Text(
              'Admin',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _kBlue,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatsErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _StatsErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load image stats: $message',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ImageUploadStats {
  final List<_ImageUploadRow> rows;

  const _ImageUploadStats(this.rows);

  int get total => rows.length;
  int get withImages => rows.where((row) => row.hasImage).length;
  int get firebaseUploads => rows.where((row) => row.isFirebaseUpload).length;
  int get missingActive => missingRows.length;

  List<_ImageUploadRow> get missingRows =>
      rows.where((row) => !row.entry.isActive ? false : !row.hasImage).toList();
}

class _ImageUploadRow {
  final FoodEntry entry;
  final bool hasAdminEntry;

  const _ImageUploadRow({required this.entry, required this.hasAdminEntry});

  bool get hasImage => (entry.imageUrl ?? '').trim().isNotEmpty;

  bool get isFirebaseUpload {
    final url = (entry.imageUrl ?? '').toLowerCase();
    return url.contains('firebasestorage.googleapis.com') ||
        url.contains('firebasestorage.app') ||
        url.contains('food_images%2f') ||
        url.contains('food_images/');
  }
}
