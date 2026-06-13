import 'package:calscan/logic/crud_records.dart';
import 'package:calscan/logic/food_lookup_service.dart';
import 'package:calscan/logic/offline_write.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

Future<void> showManualRecordDialog(
  BuildContext context, {
  String? mealId,
  Map<String, dynamic>? initialData,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _ManualRecordSheet(mealId: mealId, initialData: initialData),
  );
}

class _ManualMealItem {
  final String? foodKey;
  final TextEditingController nameController;
  final TextEditingController caloriesController;
  final TextEditingController servingController;

  /// Selected archetype portion option index. Only meaningful for preset foods
  /// (foodKey != null). -1 means "custom calories" (user typed a number directly).
  int optionIndex;

  _ManualMealItem({
    this.foodKey,
    required String name,
    required double calories,
    required String serving,
    this.optionIndex = -1,
  }) : nameController = TextEditingController(text: name),
       caloriesController = TextEditingController(
         text: calories <= 0
             ? ''
             : calories == calories.roundToDouble()
             ? calories.round().toString()
             : calories.toStringAsFixed(1),
       ),
       servingController = TextEditingController(text: serving);

  double get calories => double.tryParse(caloriesController.text.trim()) ?? 0.0;

  void setCalories(double value) {
    caloriesController.text = value <= 0
        ? ''
        : value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
  }

  void dispose() {
    nameController.dispose();
    caloriesController.dispose();
    servingController.dispose();
  }
}

class _ManualRecordSheet extends StatefulWidget {
  final String? mealId;
  final Map<String, dynamic>? initialData;

  const _ManualRecordSheet({this.mealId, this.initialData});

  @override
  State<_ManualRecordSheet> createState() => _ManualRecordSheetState();
}

class _ManualRecordSheetState extends State<_ManualRecordSheet> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _lookup = FoodLookupService();
  final _recordService = RecordService();

  final List<_ManualMealItem> _items = [];
  List<FoodEntry> _suggestions = [];
  DateTime _mealDateTime = DateTime.now();
  bool _isSaving = false;

  bool get _isEditing => widget.mealId != null;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadInitialMeal();
    if (_items.isEmpty) _items.add(_blankItem());
  }

  void _loadInitialMeal() {
    final data = widget.initialData;
    if (data == null) return;

    final timestamp = data['timestamp'];
    if (timestamp is Timestamp) _mealDateTime = timestamp.toDate();

    final rawItems = data['items'];
    if (rawItems is List && rawItems.isNotEmpty) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        _items.add(
          _ManualMealItem(
            foodKey: raw['foodKey']?.toString(),
            name: raw['name']?.toString() ?? 'Food',
            calories: (raw['calories'] as num?)?.toDouble() ?? 0,
            serving:
                raw['serving']?.toString() ??
                raw['portion']?.toString() ??
                '1 serving',
          ),
        );
      }
      return;
    }

    _items.add(
      _ManualMealItem(
        name: data['mealName']?.toString() ?? 'Meal',
        calories: (data['calories'] as num?)?.toDouble() ?? 0,
        serving: data['portion']?.toString() ?? '1 serving',
      ),
    );
  }

  _ManualMealItem _blankItem({String name = ''}) {
    return _ManualMealItem(name: name, calories: 0, serving: '1 serving');
  }

  bool _isBlankItem(_ManualMealItem item) {
    return item.nameController.text.trim().isEmpty &&
        item.caloriesController.text.trim().isEmpty;
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _searchFocus.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  double get _totalCalories =>
      _items.fold(0, (total, item) => total + item.calories);

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }

    final matches =
        _lookup.allEntries.where((food) {
          return food.displayName.toLowerCase().contains(query) ||
              food.key.toLowerCase().contains(query);
        }).toList()..sort((a, b) {
          final aStarts = a.displayName.toLowerCase().startsWith(query) ? 0 : 1;
          final bStarts = b.displayName.toLowerCase().startsWith(query) ? 0 : 1;
          final byPrefix = aStarts.compareTo(bStarts);
          return byPrefix != 0
              ? byPrefix
              : a.displayName.compareTo(b.displayName);
        });

    setState(() => _suggestions = matches.take(7).toList());
  }

  void _addPresetFood(FoodEntry food) {
    final archetype = _lookup.getArchetype(food.key);
    final defIdx = archetype.defaultIndex;
    final item = _ManualMealItem(
      foodKey: food.key,
      name: food.displayName,
      calories: _lookup.getCaloriesForOption(food.key, defIdx),
      serving: archetype.option(defIdx).label,
      optionIndex: defIdx,
    );
    _addItem(item, replaceBlank: true);
  }

  void _addCustomFood() {
    final name = _searchController.text.trim();
    _addItem(_blankItem(name: name), replaceBlank: true);
  }

  void _addItem(_ManualMealItem item, {bool replaceBlank = false}) {
    setState(() {
      if (replaceBlank && _items.length == 1 && _isBlankItem(_items.single)) {
        _items.single.dispose();
        _items[0] = item;
      } else {
        _items.add(item);
      }
      _suggestions = [];
    });
    _searchController.clear();
    _searchFocus.unfocus();
  }

  void _removeItem(int index) {
    final removed = _items.removeAt(index);
    removed.dispose();
    if (_items.isEmpty) _items.add(_blankItem());
    setState(() {});
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _mealDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _mealDateTime = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _mealDateTime.hour,
        _mealDateTime.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_mealDateTime),
    );
    if (selected == null || !mounted) return;

    final candidate = DateTime(
      _mealDateTime.year,
      _mealDateTime.month,
      _mealDateTime.day,
      selected.hour,
      selected.minute,
    );
    setState(() {
      _mealDateTime = candidate.isAfter(DateTime.now())
          ? DateTime.now()
          : candidate;
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      _showMessage('Add at least one food to this meal.');
      return;
    }
    if (FirebaseAuth.instance.currentUser == null) {
      _showMessage('You must be logged in to save a record.');
      return;
    }

    for (final item in _items) {
      if (item.nameController.text.trim().isEmpty) {
        _showMessage('Each food needs a name.');
        return;
      }
      if (item.calories <= 0) {
        _showMessage('Enter calories greater than 0 for each food.');
        return;
      }
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);

    try {
      final itemData = _items
          .map(
            (item) => {
              if (item.foodKey != null) 'foodKey': item.foodKey,
              'name': item.nameController.text.trim(),
              'serving': item.servingController.text.trim().isEmpty
                  ? '1 serving'
                  : item.servingController.text.trim(),
              'calories': item.calories,
            },
          )
          .toList();

      double totalProtein = 0, totalCarbs = 0, totalFat = 0;
      for (final item in _items) {
        if (item.foodKey != null && item.optionIndex >= 0) {
          final macros =
              _lookup.getMacrosForOption(item.foodKey!, item.optionIndex);
          totalProtein += macros.protein;
          totalCarbs += macros.carbs;
          totalFat += macros.fat;
        }
      }

      final mealData = <String, dynamic>{
        'mealName': _items
            .map((item) => item.nameController.text.trim())
            .join(' + '),
        'calories': _totalCalories,
        'protein': totalProtein,
        'carbs': totalCarbs,
        'fat': totalFat,
        'portion': _items.length == 1
            ? itemData.single['serving']
            : '${_items.length} item combo',
        'source': 'manual',
        'items': itemData,
        'timestamp': Timestamp.fromDate(_mealDateTime),
      };

      final status = _isEditing
          ? await _recordService.updateMeal(widget.mealId!, mealData)
          : await _recordService.addMeal(mealData);

      if (!mounted) return;
      Navigator.pop(context);
      final action = _isEditing ? 'updated' : 'added';
      final suffix = status == FirestoreWriteStatus.queued
          ? ' Saved offline. Syncs when online.'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Meal $action.$suffix'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showMessage('Unable to save meal: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.94,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 20),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isEditing
                        ? const [Color(0xFF6366F1), Color(0xFF8B5CF6)]
                        : const [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isEditing ? Icons.edit_rounded : Icons.add_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
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
                    Text(
                      _isEditing
                          ? 'Update food items or adjust portions'
                          : 'Search or enter foods manually',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.close,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Optional: search food presets...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? IconButton(
                      tooltip: 'Add custom food',
                      onPressed: _addCustomFood,
                      icon: const Icon(Icons.add),
                    )
                  : IconButton(
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.clear),
                    ),
            ),
          ),
          if (_searchController.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 230),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.dividerColor),
              ),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  ..._suggestions.map(
                    (food) => ListTile(
                      dense: true,
                      title: Text(food.displayName),
                      subtitle: Text(
                        food.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        '${food.baseCalories.round()} kcal',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () => _addPresetFood(food),
                    ),
                  ),
                  Divider(height: 1, color: theme.dividerColor),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text(
                      'Use "${_searchController.text.trim()}" as the name',
                    ),
                    subtitle: const Text('Calories and serving stay editable'),
                    onTap: _addCustomFood,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DateTimeButton(
                  icon: Icons.calendar_today_outlined,
                  label: DateFormat('EEE, d MMM yyyy').format(_mealDateTime),
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateTimeButton(
                  icon: Icons.schedule,
                  label: DateFormat.jm().format(_mealDateTime),
                  onTap: _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: _items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index < _items.length) {
                  return _MealItemCard(
                    item: _items[index],
                    archetype: _items[index].foodKey != null
                        ? _lookup.getArchetype(_items[index].foodKey!)
                        : null,
                    onRemove: () => _removeItem(index),
                    onCaloriesChanged: () => setState(() {}),
                    onOptionSelected: (i) {
                      final item = _items[index];
                      final key = item.foodKey;
                      if (key == null) return;
                      setState(() {
                        item.optionIndex = i;
                        item.setCalories(_lookup.getCaloriesForOption(key, i));
                        item.servingController.text =
                            _lookup.getArchetype(key).option(i).label;
                      });
                    },
                  );
                }
                return OutlinedButton.icon(
                  onPressed: () => _addItem(_blankItem()),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Add another food'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF4B2B).withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_items.length} ${_items.length == 1 ? 'item' : 'items'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const Spacer(),
                Text(
                  '${_totalCalories.round()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'kcal',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(_isEditing ? Icons.save_outlined : Icons.add_task),
              label: Text(
                _isSaving
                    ? 'Saving...'
                    : _isEditing
                    ? 'Save Changes'
                    : 'Log Meal',
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _MealItemCard extends StatelessWidget {
  final _ManualMealItem item;
  final ArchetypeInfo? archetype;
  final VoidCallback onRemove;
  final VoidCallback onCaloriesChanged;
  final ValueChanged<int> onOptionSelected;

  const _MealItemCard({
    required this.item,
    required this.archetype,
    required this.onRemove,
    required this.onCaloriesChanged,
    required this.onOptionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7E00).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.restaurant_rounded,
                    color: Color(0xFFFF7E00),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: item.nameController,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Food name',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            indent: 14,
            endIndent: 14,
            color: theme.dividerColor,
          ),
          // Preset food: archetype portion chips. Custom food: free-text serving.
          if (archetype != null && archetype!.options.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(archetype!.options.length, (i) {
                    final opt = archetype!.options[i];
                    final selected = i == item.optionIndex;
                    return GestureDetector(
                      onTap: () => onOptionSelected(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFFF7E00)
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFFFF7E00)
                                : theme.dividerColor,
                          ),
                        ),
                        child: Text(
                          opt.label,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: item.caloriesController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    onChanged: (_) {
                      // Manual edit detaches from the archetype option.
                      item.optionIndex = -1;
                      onCaloriesChanged();
                    },
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Calories',
                      suffixText: 'kcal',
                      suffixStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: item.servingController,
                    decoration: const InputDecoration(
                      labelText: 'Serving',
                      hintText: '1 plate',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DateTimeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DateTimeButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      ),
    );
  }
}
