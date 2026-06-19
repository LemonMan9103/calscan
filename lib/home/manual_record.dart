import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:calscan/logic/crud_records.dart';
import 'package:calscan/logic/food_lookup_service.dart';
import 'package:calscan/logic/offline_write.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const _kOrange = Color(0xFFFF7E00);

Future<void> showManualRecordDialog(
  BuildContext context, {
  String? mealId,
  Map<String, dynamic>? initialData,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _ManualRecordSheet(mealId: mealId, initialData: initialData),
  );
}

class _MealItem {
  final String? key;
  String name;
  bool isCustom;
  int optionIndex;
  int count;
  double customCalories;
  String customServing;

  _MealItem({
    required this.key,
    required this.name,
    required this.isCustom,
    this.optionIndex = 0,
    this.count = 1,
    this.customCalories = 0,
    this.customServing = '1 serving',
  });
}

class _ManualRecordSheet extends StatefulWidget {
  final String? mealId;
  final Map<String, dynamic>? initialData;

  const _ManualRecordSheet({this.mealId, this.initialData});

  @override
  State<_ManualRecordSheet> createState() => _ManualRecordSheetState();
}

class _ManualRecordSheetState extends State<_ManualRecordSheet> {
  final _formKey = GlobalKey<FormState>();
  final FoodLookupService _foods = FoodLookupService();
  final RecordService _records = RecordService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _mealNameController = TextEditingController();

  final List<_MealItem> _items = [];
  String _searchQuery = '';
  DateTime _timestamp = DateTime.now();
  bool _saving = false;
  bool _attemptedSave = false;

  bool get _isEditing => widget.mealId != null;

  double get _totalCalories =>
      _items.fold(0.0, (total, item) => total + _itemCalories(item));

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadInitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mealNameController.dispose();
    super.dispose();
  }

  void _loadInitial() {
    final data = widget.initialData!;
    _mealNameController.text = data['mealName'] as String? ?? '';
    final ts = data['timestamp'];
    if (ts is Timestamp) _timestamp = ts.toDate();

    final rawItems = data['items'];
    if (rawItems is! List) return;

    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final key = raw['key'] as String?;
      final entry = key == null ? null : _foods.lookup(key);
      if (entry != null) {
        final arch = _foods.getArchetype(key!);
        _items.add(
          _MealItem(
            key: key,
            name: entry.displayName,
            isCustom: false,
            optionIndex:
                (raw['optionIndex'] as num?)?.toInt() ?? arch.defaultIndex,
            count: (raw['count'] as num?)?.toInt() ?? arch.defaultCount,
          ),
        );
      } else {
        _items.add(
          _MealItem(
            key: null,
            name: raw['name'] as String? ?? 'Custom food',
            isCustom: true,
            customCalories: (raw['calories'] as num?)?.toDouble() ?? 0,
            customServing: raw['serving'] as String? ?? '1 serving',
          ),
        );
      }
    }
  }

  double _itemCalories(_MealItem item) {
    // used for calculating calories, custom food use ur own input
    if (item.isCustom) return item.customCalories;
    final arch = _foods.getArchetype(item.key!);
    return arch.isCounter
        ? _foods.getCaloriesForCount(item.key!, item.count)
        : _foods.getCaloriesForOption(item.key!, item.optionIndex);
  }

  ({double protein, double carbs, double fat}) _itemMacros(_MealItem item) {
    if (item.isCustom) return (protein: 0, carbs: 0, fat: 0);
    final arch = _foods.getArchetype(item.key!);
    return arch.isCounter
        ? _foods.getMacrosForCount(item.key!, item.count)
        : _foods.getMacrosForOption(item.key!, item.optionIndex);
  }

  String _itemServing(_MealItem item) {
    if (item.isCustom) {
      final serving = item.customServing.trim();
      return serving.isEmpty ? '1 serving' : serving;
    }
    final arch = _foods.getArchetype(item.key!);
    return arch.isCounter
        ? arch.countLabel(item.count)
        : arch.option(item.optionIndex).label;
  }

  void _addPreset(FoodEntry entry) {
    final arch = _foods.getArchetype(entry.key);
    setState(() {
      _items.add(
        _MealItem(
          key: entry.key,
          name: entry.displayName,
          isCustom: false,
          optionIndex: arch.defaultIndex,
          count: arch.defaultCount,
        ),
      );
      _clearSearch();
    });
  }

  void _addCustom({String? name}) {
    final customName = (name ?? _searchQuery).trim();
    setState(() {
      _items.add(
        _MealItem(
          key: null,
          name: customName.isEmpty ? 'Custom food' : customName,
          isCustom: true,
          customCalories: 0,
          customServing: '1 serving',
        ),
      );
      _clearSearch();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchQuery = '';
  }

  void _removeItem(int index) => setState(() => _items.removeAt(index));

  Future<void> _save() async {
    // validate first before send to firebase
    setState(() => _attemptedSave = true);
    final formOk = _formKey.currentState?.validate() ?? false;
    if (_items.isEmpty) {
      _toast('Add at least one food item.');
      return;
    }
    if (!formOk) {
      _toast('Check the highlighted fields.');
      return;
    }

    setState(() => _saving = true);

    double totalCal = 0, totalP = 0, totalC = 0, totalF = 0;
    final itemMaps = <Map<String, dynamic>>[];

    for (final item in _items) {
      final cal = _itemCalories(item);
      final macros = _itemMacros(item);
      totalCal += cal;
      totalP += macros.protein;
      totalC += macros.carbs;
      totalF += macros.fat;
      itemMaps.add({
        'key': item.key,
        'name': item.name.trim(),
        'calories': cal.roundToDouble(),
        'serving': _itemServing(item),
        if (!item.isCustom) 'optionIndex': item.optionIndex,
        if (!item.isCustom) 'count': item.count,
        'protein': macros.protein,
        'carbs': macros.carbs,
        'fat': macros.fat,
        'isCustom': item.isCustom,
      });
    }

    final fallbackName = _items.map((i) => i.name.trim()).join(' + ');
    final mealName = _mealNameController.text.trim().isNotEmpty
        ? _mealNameController.text.trim()
        : fallbackName;

    final mealData = <String, dynamic>{
      // this shape is used by home, records, edit meal
      'mealName': mealName,
      'calories': totalCal.round(),
      'protein': totalP,
      'carbs': totalC,
      'fat': totalF,
      'items': itemMaps,
      'timestamp': Timestamp.fromDate(_timestamp),
      'source': 'manual',
    };

    try {
      final status = _isEditing
          ? await _records.updateMeal(widget.mealId!, mealData)
          : await _records.addMeal(mealData);
      if (!mounted) return;
      Navigator.pop(context);
      _toast(
        status == FirestoreWriteStatus.queued
            ? 'Saved offline. Syncs later.'
            : _isEditing
            ? 'Meal updated.'
            : 'Meal logged.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save meal: $e');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _timestamp,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_timestamp),
    );
    if (!mounted) return;

    setState(() {
      _timestamp = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _timestamp.hour,
        time?.minute ?? _timestamp.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildHandle(theme),
                _buildHeader(theme),
                _buildSearchBar(theme),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 20 + bottomInset),
                    children: [
                      if (_searchQuery.isNotEmpty) _buildSuggestions(theme),
                      if (_items.isEmpty)
                        _buildEmptyState(theme)
                      else ...[
                        _buildMealNameField(theme),
                        const SizedBox(height: 12),
                        ..._items.asMap().entries.map(
                          (entry) =>
                              _buildItemCard(theme, entry.key, entry.value),
                        ),
                        _buildAddEmptyFoodButton(theme),
                      ],
                    ],
                  ),
                ),
                _buildBottomBar(theme),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHandle(ThemeData theme) => Container(
    margin: const EdgeInsets.only(top: 10, bottom: 6),
    width: 42,
    height: 4,
    decoration: BoxDecoration(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(999),
    ),
  );

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _kOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _isEditing ? Icons.edit_note_rounded : Icons.playlist_add_rounded,
              color: _kOrange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing ? 'Edit Meal' : 'Add Meal',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: _pickDateTime,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule, size: 15, color: _kOrange),
                        const SizedBox(width: 5),
                        Text(
                          DateFormat('MMM d, yyyy - h:mm a').format(_timestamp),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: _kOrange,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.expand_more,
                          size: 16,
                          color: _kOrange,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search food',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () => setState(_clearSearch),
                )
              : null,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHigh,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildMealNameField(ThemeData theme) {
    return TextFormField(
      controller: _mealNameController,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Meal name',
        hintText: 'Optional, e.g. Lunch',
        prefixIcon: Icon(Icons.label_outline),
      ),
    );
  }

  Widget _buildSuggestions(ThemeData theme) {
    final query = _searchQuery.toLowerCase().trim();
    final matches = _foods.allEntries
        .where((entry) => entry.displayName.toLowerCase().contains(query))
        .take(8)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'No matching food in library.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            ...matches.map(
              (entry) => _buildSuggestionTile(
                icon: Icons.restaurant_menu,
                title: entry.displayName,
                subtitle: _categoryLabel(entry.category),
                color: _kOrange,
                onTap: () => _addPreset(entry),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuggestionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      minVerticalPadding: 10,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.add_circle_outline, color: color),
      onTap: onTap,
    );
  }

  Widget _buildItemCard(ThemeData theme, int index, _MealItem item) {
    final calories = _itemCalories(item);
    final macros = _itemMacros(item);
    final hasMacros = macros.protein + macros.carbs + macros.fat > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name.trim().isEmpty ? 'Custom food' : item.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.isCustom
                          ? 'Custom entry'
                          : _categoryLabel(_foods.getCategory(item.key!)),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${calories.round()} kcal',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: _kOrange,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (hasMacros)
                    Text(
                      'P ${macros.protein.toInt()}g C ${macros.carbs.toInt()}g F ${macros.fat.toInt()}g',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Remove ${item.name}',
                icon: const Icon(Icons.delete_outline, size: 21),
                color: theme.colorScheme.onSurfaceVariant,
                onPressed: () => _removeItem(index),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (item.isCustom)
            _buildCustomControls(theme, item)
          else
            _buildPresetControls(theme, item),
        ],
      ),
    );
  }

  Widget _buildPresetControls(ThemeData theme, _MealItem item) {
    final arch = _foods.getArchetype(item.key!);
    if (arch.isCounter) {
      return Row(
        children: [
          Expanded(
            child: Text(
              arch.archetypeLabel,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _stepperButton(
            icon: Icons.remove,
            label: 'Decrease ${item.name}',
            onTap: item.count > arch.minCount
                ? () => setState(() => item.count--)
                : null,
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 86),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              arch.countLabel(item.count),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _stepperButton(
            icon: Icons.add,
            label: 'Increase ${item.name}',
            onTap: () => setState(() => item.count++),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(arch.options.length, (index) {
        final selected = index == item.optionIndex;
        return ChoiceChip(
          label: Text(arch.option(index).label),
          selected: selected,
          onSelected: (_) => setState(() => item.optionIndex = index),
          showCheckmark: false,
          selectedColor: _kOrange,
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          labelStyle: TextStyle(
            color: selected ? Colors.white : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
          side: BorderSide(color: selected ? _kOrange : theme.dividerColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        );
      }),
    );
  }

  Widget _buildCustomControls(ThemeData theme, _MealItem item) {
    return Column(
      children: [
        TextFormField(
          key: ValueKey('name-${identityHashCode(item)}'),
          initialValue: item.name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Food name',
            prefixIcon: Icon(Icons.edit_outlined),
          ),
          validator: (value) {
            if ((value ?? '').trim().isEmpty) return 'Enter a food name';
            return null;
          },
          onChanged: (value) => setState(() => item.name = value),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('cal-${identityHashCode(item)}'),
                initialValue: item.customCalories == 0
                    ? ''
                    : item.customCalories.toStringAsFixed(0),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Calories',
                  suffixText: 'kcal',
                  prefixIcon: Icon(Icons.local_fire_department_outlined),
                ),
                validator: (value) {
                  final calories = double.tryParse((value ?? '').trim());
                  if (calories == null || calories <= 0) {
                    return 'Enter kcal';
                  }
                  return null;
                },
                onChanged: (value) => setState(
                  () =>
                      item.customCalories = double.tryParse(value.trim()) ?? 0,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                key: ValueKey('serving-${identityHashCode(item)}'),
                initialValue: item.customServing,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Serving',
                  hintText: '1 cup',
                  prefixIcon: Icon(Icons.scale_outlined),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) return 'Enter serving';
                  return null;
                },
                onChanged: (value) => item.customServing = value,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAddEmptyFoodButton(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: OutlinedButton.icon(
        onPressed: () => _addCustom(),
        icon: const Icon(Icons.add),
        label: const Text('Add empty custom food'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _kOrange,
          side: const BorderSide(color: _kOrange),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _stepperButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton.filledTonal(
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: onTap == null
              ? Colors.grey.withValues(alpha: 0.10)
              : _kOrange.withValues(alpha: 0.14),
          foregroundColor: onTap == null ? Colors.grey : _kOrange,
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 28),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _kOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.restaurant, size: 34, color: _kOrange),
          ),
          const SizedBox(height: 16),
          Text(
            'Start building your meal',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Search the food library or add a custom food with your own calories.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => _addCustom(),
              icon: const Icon(Icons.add),
              label: const Text('Add Custom Food'),
            ),
          ),
          if (_attemptedSave) ...[
            const SizedBox(height: 12),
            Text(
              'Add at least one item before saving.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_items.length} ${_items.length == 1 ? 'item' : 'items'}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_totalCalories.round()} kcal',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: _kOrange,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 170,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _kOrange.withValues(alpha: 0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _isEditing ? 'Update Meal' : 'Log Meal',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(String category) {
    if (category.isEmpty) return 'Food library';
    return category
        .split('_')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }
}
