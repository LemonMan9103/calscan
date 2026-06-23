import 'package:flutter/material.dart';
import 'package:calscan/logic/food_lookup_service.dart';
import 'package:calscan/logic/crud_records.dart';
import 'package:calscan/logic/offline_write.dart' show FirestoreWriteStatus;
import 'package:cloud_firestore/cloud_firestore.dart';

class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key});

  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage> {
  final FoodLookupService _lookup = FoodLookupService();
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _showTiles = true;
  List<FoodEntry> _allFoods = [];

  static const _groupOrder = [
    'full_meals',
    'rice_noodles',
    'proteins',
    'sides',
    'snacks_drinks',
  ];
  static const _groupHeaders = {
    'full_meals': 'Full Meals',
    'rice_noodles': 'Rice & Noodles',
    'proteins': 'Proteins',
    'sides': 'Sides & Condiments',
    'snacks_drinks': 'Snacks & Drinks',
  };

  @override
  void initState() {
    super.initState();
    _syncFoods();
    _refreshFoods();
  }

  void _syncFoods() {
    _allFoods = _lookup.allEntries.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  Future<void> _refreshFoods() async {
    await _lookup.refreshRemoteEntries();
    if (!mounted) return;
    setState(_syncFoods);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FoodEntry> get _filtered {
    if (_query.isEmpty) return _allFoods;
    final q = _query.toLowerCase();
    return _allFoods
        .where(
          (f) =>
              f.displayName.toLowerCase().contains(q) ||
              f.description.toLowerCase().contains(q),
        )
        .toList();
  }

  Map<String, List<FoodEntry>> get _grouped {
    final result = <String, List<FoodEntry>>{};
    for (final food in _allFoods) {
      result.putIfAbsent(_foodGroup(food), () => []).add(food);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        title: Text(
          'Nutrition Library',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: _showTiles ? 'Switch to list' : 'Switch to tiles',
            onPressed: () => setState(() => _showTiles = !_showTiles),
            icon: Icon(_showTiles ? Icons.view_list_rounded : Icons.grid_view),
          ),
          IconButton(
            tooltip: 'Refresh foods',
            onPressed: _refreshFoods,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Container(
            color: theme.colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search food...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFFFF7E00),
        onRefresh: _refreshFoods,
        child: _query.isNotEmpty ? _buildSearchResults() : _buildGroupedList(),
      ),
    );
  }

  Widget _buildSearchResults() {
    final results = _filtered;
    if (results.isEmpty) return _buildEmpty();
    if (!_showTiles) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: results.length,
        itemBuilder: (context, index) => _FoodListTile(entry: results[index]),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.82,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) => _FoodCard(entry: results[index]),
    );
  }

  Widget _buildGroupedList() {
    final grouped = _grouped;
    return CustomScrollView(
      slivers: [
        for (final group in _groupOrder) ...[
          if (grouped[group]?.isNotEmpty ?? false) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(title: _groupHeaders[group]!),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: _showTiles
                  ? SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.82,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _FoodCard(entry: grouped[group]![index]),
                        childCount: grouped[group]!.length,
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _FoodListTile(entry: grouped[group]![index]),
                        childCount: grouped[group]!.length,
                      ),
                    ),
            ),
          ],
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            'No food matching "$_query"',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

String _foodGroup(FoodEntry entry) {
  final arch = entry.archetypeId;
  if (entry.category == 'whole_dish' || arch == 'whole_meal') {
    return 'full_meals';
  }
  if (arch == 'grain_rice' || arch == 'noodle_plate' || arch == 'slice_bread') {
    return 'rice_noodles';
  }
  if (arch == 'pcs_chicken' || arch == 'pcs_egg' || arch == 'satay_sticks') {
    return 'proteins';
  }
  if (entry.category == 'snack' ||
      arch == 'cup_drink' ||
      arch == 'cup_snack' ||
      arch == 'slice_pizza') {
    return 'snacks_drinks';
  }
  return 'sides';
}

String _foodGroupLabel(FoodEntry entry) =>
    _NutritionPageState._groupHeaders[_foodGroup(entry)] ?? 'Food';

({IconData icon, Color color}) _foodVisual(FoodEntry entry) {
  switch (_foodGroup(entry)) {
    case 'full_meals':
      return (
        icon: Icons.dinner_dining_rounded,
        color: const Color(0xFF4D82F5),
      );
    case 'rice_noodles':
      return (icon: Icons.rice_bowl_rounded, color: const Color(0xFFFF7E00));
    case 'proteins':
      return (icon: Icons.egg_alt_rounded, color: const Color(0xFFEAB308));
    case 'snacks_drinks':
      return (icon: Icons.local_cafe_rounded, color: const Color(0xFF30C060));
    default:
      return (icon: Icons.soup_kitchen_rounded, color: const Color(0xFF8B5CF6));
  }
}

class _FoodVisualBox extends StatelessWidget {
  final FoodEntry entry;
  final IconData icon;
  final Color color;
  final double width;
  final double height;
  final double iconSize;

  const _FoodVisualBox({
    required this.entry,
    required this.icon,
    required this.color,
    required this.width,
    required this.height,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = entry.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: width,
        height: height,
        color: color.withValues(alpha: 0.12),
        child: imageUrl == null
            ? Icon(icon, color: color, size: iconSize)
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.broken_image_outlined, color: color),
              ),
      ),
    );
  }
}

class _FoodCard extends StatelessWidget {
  final FoodEntry entry;

  const _FoodCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = _foodVisual(entry);
    final catColor = visual.color;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FoodVisualBox(
                entry: entry,
                icon: visual.icon,
                color: catColor,
                height: 74,
                width: double.infinity,
                iconSize: 34,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _foodGroupLabel(entry),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: catColor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${entry.baseCalories.toInt()} kcal',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFFF7E00),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FoodDetailSheet(entry: entry),
    );
  }
}

class _FoodListTile extends StatelessWidget {
  final FoodEntry entry;

  const _FoodListTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = _foodVisual(entry);
    final hasMacros = entry.baseProtein + entry.baseCarbs + entry.baseFat > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: () => _showDetail(context),
        minVerticalPadding: 12,
        leading: _FoodVisualBox(
          entry: entry,
          icon: visual.icon,
          color: visual.color,
          width: 44,
          height: 44,
        ),
        title: Text(
          entry.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _foodGroupLabel(entry),
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (hasMacros)
              Text(
                'P ${entry.baseProtein.toInt()}g · C ${entry.baseCarbs.toInt()}g · F ${entry.baseFat.toInt()}g',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.72,
                  ),
                  fontSize: 11,
                ),
              ),
          ],
        ),
        trailing: Text(
          '${entry.baseCalories.toInt()} kcal',
          style: const TextStyle(
            color: Color(0xFFFF7E00),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FoodDetailSheet(entry: entry),
    );
  }
}

class _FoodDetailSheet extends StatefulWidget {
  final FoodEntry entry;

  const _FoodDetailSheet({required this.entry});

  @override
  State<_FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends State<_FoodDetailSheet> {
  final FoodLookupService _lookup = FoodLookupService();
  final RecordService _recordService = RecordService();
  late int _selectedIndex;
  late int _count;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _lookup.getDefaultPortionIndex(widget.entry.key);
    _count = _lookup.getArchetype(widget.entry.key).defaultCount;
  }

  ArchetypeInfo get _archetype => _lookup.getArchetype(widget.entry.key);
  double get _calories => _archetype.isCounter
      ? _lookup.getCaloriesForCount(widget.entry.key, _count)
      : _lookup.getCaloriesForOption(widget.entry.key, _selectedIndex);
  ({double protein, double carbs, double fat}) get _macros =>
      _archetype.isCounter
      ? _lookup.getMacrosForCount(widget.entry.key, _count)
      : _lookup.getMacrosForOption(widget.entry.key, _selectedIndex);
  String get _portionLabel => _archetype.isCounter
      ? _archetype.countLabel(_count)
      : _archetype.option(_selectedIndex).label;

  Future<void> _addToRecord() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final macros = _macros;
      final status = await _recordService.addMeal({
        'mealName': widget.entry.displayName,
        'calories': _calories,
        'protein': macros.protein,
        'carbs': macros.carbs,
        'fat': macros.fat,
        'portion': _portionLabel,
        'items': [
          {
            'key': widget.entry.key,
            'name': widget.entry.displayName,
            'calories': _calories.roundToDouble(),
            'serving': _portionLabel,
            if (_archetype.isCounter) 'count': _count,
            if (!_archetype.isCounter) 'optionIndex': _selectedIndex,
            'protein': macros.protein,
            'carbs': macros.carbs,
            'fat': macros.fat,
            'isCustom': false,
          },
        ],
        'source': 'manual',
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == FirestoreWriteStatus.queued
                ? 'Saved offline. Syncs when online.'
                : '${widget.entry.displayName} logged!',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final macros = _macros;
    final visual = _foodVisual(widget.entry);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.25,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  _FoodVisualBox(
                    entry: widget.entry,
                    icon: visual.icon,
                    color: visual.color,
                    width: double.infinity,
                    height: 128,
                    iconSize: 42,
                  ),
                  const SizedBox(height: 16),
                  // Title
                  Text(
                    widget.entry.displayName,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.entry.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Portion selector
                  Text(
                    'Serving size',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _archetype.isCounter
                      ? _buildCounterSelector(theme)
                      : _buildChipSelector(theme),
                  const SizedBox(height: 20),

                  // Calorie + macros strip
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      key: ValueKey(_selectedIndex),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.local_fire_department,
                            color: Colors.white,
                            size: 26,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_calories.toInt()} kcal',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (macros.protein + macros.carbs + macros.fat >
                                    0)
                                  Text(
                                    'P ${macros.protein.toInt()}g · C ${macros.carbs.toInt()}g · F ${macros.fat.toInt()}g',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Add to record button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _addToRecord,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.add_circle_outline,
                              color: Colors.white,
                            ),
                      label: Text(
                        _saving ? 'Saving...' : 'Add to Records',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF7E00),
                        disabledBackgroundColor: Colors.orange.shade300,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipSelector(ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(_archetype.options.length, (i) {
        final opt = _archetype.options[i];
        final selected = i == _selectedIndex;
        return ChoiceChip(
          label: Text(opt.label),
          selected: selected,
          onSelected: (_) => setState(() => _selectedIndex = i),
          selectedColor: const Color(0xFFFF7E00),
          showCheckmark: false,
          labelStyle: TextStyle(
            color: selected ? Colors.white : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          side: BorderSide(
            color: selected ? const Color(0xFFFF7E00) : theme.dividerColor,
          ),
        );
      }),
    );
  }

  Widget _buildCounterSelector(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _archetype.archetypeLabel,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: _count > _archetype.minCount
                ? () => setState(() => _count--)
                : null,
            icon: const Icon(Icons.remove),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _archetype.countLabel(_count),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton.filledTonal(
            onPressed: () => setState(() => _count++),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
