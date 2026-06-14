import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:calscan/logic/food_lookup_service.dart';
import 'package:calscan/logic/crud_records.dart';
import 'package:calscan/logic/offline_write.dart';

const _kOrange = Color(0xFFFF7E00);

/// Opens the Build-a-Meal / Edit-Meal bottom sheet.
///
/// Pass [mealId] + [initialData] to edit an existing meal; omit both to
/// create a new one.
Future<void> showManualRecordDialog(
  BuildContext context, {
  String? mealId,
  Map<String, dynamic>? initialData,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ManualRecordSheet(mealId: mealId, initialData: initialData),
  );
}

/// A single food line inside the meal being built.
class _MealItem {
  /// Preset food key, or null for a custom entry.
  final String? key;
  String name;

  // Archetype selection state.
  bool isCustom;

  // chips state
  int optionIndex;
  // counter state
  int count;

  // custom-entry editable values
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
  final FoodLookupService _foods = FoodLookupService();
  final RecordService _records = RecordService();

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _mealNameController = TextEditingController();

  final List<_MealItem> _items = [];
  String _searchQuery = '';
  DateTime _timestamp = DateTime.now();
  bool _saving = false;

  bool get _isEditing => widget.mealId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadInitial();
  }

  void _loadInitial() {
    final data = widget.initialData!;
    _mealNameController.text = data['mealName'] as String? ?? '';
    final ts = data['timestamp'];
    if (ts is Timestamp) _timestamp = ts.toDate();

    final rawItems = data['items'];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final key = raw['key'] as String?;
        final entry = key == null ? null : _foods.lookup(key);
        if (entry != null) {
          // Restore a preset item with its saved portion selection.
          final arch = _foods.getArchetype(key!);
          _items.add(
            _MealItem(
              key: key,
              name: entry.displayName,
              isCustom: false,
              optionIndex: (raw['optionIndex'] as num?)?.toInt() ??
                  arch.defaultIndex,
              count: (raw['count'] as num?)?.toInt() ?? arch.defaultCount,
            ),
          );
        } else {
          // Restore a custom item.
          _items.add(
            _MealItem(
              key: null,
              name: raw['name'] as String? ?? 'Food',
              isCustom: true,
              customCalories: (raw['calories'] as num?)?.toDouble() ?? 0,
              customServing: raw['serving'] as String? ?? '1 serving',
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mealNameController.dispose();
    super.dispose();
  }

  // ── Calorie / macro maths ──────────────────────────────────────────────────

  double _itemCalories(_MealItem item) {
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
    if (item.isCustom) return item.customServing;
    final arch = _foods.getArchetype(item.key!);
    return arch.isCounter
        ? arch.countLabel(item.count)
        : arch.option(item.optionIndex).label;
  }

  double get _totalCalories =>
      _items.fold(0.0, (acc, item) => acc + _itemCalories(item));

  // ── Item management ────────────────────────────────────────────────────────

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
      _searchController.clear();
      _searchQuery = '';
    });
  }

  void _addCustom() {
    setState(() {
      _items.add(
        _MealItem(
          key: null,
          name: _searchQuery.trim().isEmpty ? 'Custom food' : _searchQuery.trim(),
          isCustom: true,
          customCalories: 0,
          customServing: '1 serving',
        ),
      );
      _searchController.clear();
      _searchQuery = '';
    });
  }

  void _removeItem(int index) => setState(() => _items.removeAt(index));

  // ── Save ────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_items.isEmpty) {
      _toast('Add at least one food item.');
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
        'name': item.name,
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

    final mealName = _mealNameController.text.trim().isNotEmpty
        ? _mealNameController.text.trim()
        : _items.map((i) => i.name).join(' + ');

    final mealData = <String, dynamic>{
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
            ? 'Saved offline — will sync when online.'
            : _isEditing
                ? 'Meal updated.'
                : 'Meal logged.',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('Could not save meal: $e');
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Date / time ──────────────────────────────────────────────────────────────

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

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              _buildHandle(theme),
              _buildHeader(theme),
              _buildSearchBar(theme),
              Expanded(
                child: _items.isEmpty && _searchQuery.isEmpty
                    ? _buildEmptyState(theme)
                    : ListView(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
                        children: [
                          if (_searchQuery.isNotEmpty) _buildSuggestions(theme),
                          ..._items.asMap().entries.map(
                                (e) => _buildItemCard(theme, e.key, e.value),
                              ),
                        ],
                      ),
              ),
              _buildBottomBar(theme),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHandle(ThemeData theme) => Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing ? 'Edit Meal' : 'Build a Meal',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                InkWell(
                  onTap: _pickDateTime,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 13, color: _kOrange),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('MMM d, h:mm a').format(_timestamp),
                        style: const TextStyle(
                          fontSize: 12,
                          color: _kOrange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Search foods to add…',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
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
    );
  }

  Widget _buildSuggestions(ThemeData theme) {
    final q = _searchQuery.toLowerCase();
    final matches = _foods.allEntries
        .where((e) => e.displayName.toLowerCase().contains(q))
        .take(8)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          ...matches.map(
            (e) => ListTile(
              dense: true,
              leading: const Icon(Icons.restaurant_menu,
                  color: _kOrange, size: 20),
              title: Text(e.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                e.category,
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.add_circle_outline, color: _kOrange),
              onTap: () => _addPreset(e),
            ),
          ),
          // Custom-food fallback always available.
          ListTile(
            dense: true,
            leading: const Icon(Icons.edit_note, color: Colors.grey, size: 20),
            title: Text('Add "${_searchQuery.trim()}" as custom food'),
            trailing: const Icon(Icons.add_circle_outline, color: Colors.grey),
            onTap: _addCustom,
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(ThemeData theme, int index, _MealItem item) {
    final cal = _itemCalories(item);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '${cal.round()} kcal',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _kOrange,
                  fontSize: 15,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: Colors.grey),
                onPressed: () => _removeItem(index),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
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
      // [−] N pcs [+] stepper
      return Row(
        children: [
          Text(arch.archetypeLabel,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const Spacer(),
          _stepperButton(
            icon: Icons.remove,
            onTap: item.count > arch.minCount
                ? () => setState(() => item.count--)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              arch.countLabel(item.count),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          _stepperButton(
            icon: Icons.add,
            onTap: () => setState(() => item.count++),
          ),
        ],
      );
    }

    // chips row
    return Wrap(
      spacing: 8,
      children: List.generate(arch.options.length, (i) {
        final selected = i == item.optionIndex;
        return ChoiceChip(
          label: Text(arch.option(i).label),
          selected: selected,
          onSelected: (_) => setState(() => item.optionIndex = i),
          selectedColor: _kOrange.withValues(alpha: 0.18),
          labelStyle: TextStyle(
            color: selected ? _kOrange : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: selected ? _kOrange : theme.dividerColor,
            ),
          ),
          showCheckmark: false,
        );
      }),
    );
  }

  Widget _buildCustomControls(ThemeData theme, _MealItem item) {
    return Column(
      children: [
        TextFormField(
          initialValue: item.name,
          decoration: const InputDecoration(
            labelText: 'Food name',
            isDense: true,
          ),
          onChanged: (v) => item.name = v,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue:
                    item.customCalories == 0 ? '' : item.customCalories.toStringAsFixed(0),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Calories',
                  isDense: true,
                  suffixText: 'kcal',
                ),
                onChanged: (v) => setState(
                  () => item.customCalories = double.tryParse(v) ?? 0,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                initialValue: item.customServing,
                decoration: const InputDecoration(
                  labelText: 'Serving',
                  isDense: true,
                ),
                onChanged: (v) => item.customServing = v,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stepperButton({required IconData icon, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: onTap == null
              ? Colors.grey.withValues(alpha: 0.1)
              : _kOrange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? Colors.grey : _kOrange,
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restaurant,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 14),
          Text(
            'Search above to add foods',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Build a meal from one or more items',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Total',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text(
                '${_totalCalories.round()} kcal',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: _kOrange,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
