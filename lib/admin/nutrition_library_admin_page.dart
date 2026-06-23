import 'dart:io';

import 'package:flutter/material.dart';
import 'package:calscan/logic/admin_food_library_service.dart';
import 'package:calscan/logic/food_lookup_service.dart';
import 'package:image_picker/image_picker.dart';

const _kOrange = Color(0xFFFF7E00);

class NutritionLibraryAdminPage extends StatefulWidget {
  const NutritionLibraryAdminPage({super.key});

  @override
  State<NutritionLibraryAdminPage> createState() =>
      _NutritionLibraryAdminPageState();
}

class _NutritionLibraryAdminPageState extends State<NutritionLibraryAdminPage> {
  final FoodLookupService _lookup = FoodLookupService();
  final AdminFoodLibraryService _admin = AdminFoodLibraryService();
  final TextEditingController _searchController = TextEditingController();

  late Future<_AdminFoodData> _future;
  String _query = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_AdminFoodData> _loadData() async {
    await _lookup.refreshRemoteEntries();
    final remote = await _admin.fetchAdminFoods();
    return _AdminFoodData(
      bundled: {for (final food in _lookup.bundledEntries) food.key: food},
      remote: remote,
    );
  }

  void _reload() {
    setState(() => _future = _loadData());
  }

  List<_AdminFoodRow> _visibleRows(_AdminFoodData data) {
    var rows = data.rows;
    if (_filter == 'admin') rows = rows.where((row) => row.hasAdmin).toList();
    if (_filter == 'bundled') {
      rows = rows.where((row) => row.isBundledOnly).toList();
    }
    if (_filter == 'hidden') rows = rows.where((row) => row.isHidden).toList();

    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return rows;

    return rows
        .where(
          (row) =>
              row.entry.displayName.toLowerCase().contains(query) ||
              row.entry.key.toLowerCase().contains(query) ||
              row.entry.category.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _openEditor([_AdminFoodRow? row]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FoodEditorSheet(
        initialEntry: row?.entry,
        isEditingBundledOnly: row?.isBundledOnly ?? false,
        archetypes: _lookup.allArchetypes.toList()
          ..sort((a, b) => a.archetypeLabel.compareTo(b.archetypeLabel)),
      ),
    );

    if (saved == true) {
      _toast(row == null ? 'Food added.' : 'Food saved.');
      _reload();
    }
  }

  Future<void> _toggleHidden(_AdminFoodRow row) async {
    final title = row.isHidden ? 'Restore food?' : 'Hide food?';
    final message = row.isHidden
        ? '${row.entry.displayName} will appear again in the app library.'
        : '${row.entry.displayName} will be hidden from users.';

    final ok = await _confirm(
      title: title,
      message: message,
      action: row.isHidden ? 'Restore' : 'Hide',
      destructive: !row.isHidden,
    );
    if (!ok) return;

    try {
      if (row.isHidden) {
        await _admin.saveFood(
          row.entry.copyWith(source: 'admin', isActive: true),
        );
        _toast('Food restored.');
      } else {
        await _admin.hideFood(row.entry);
        _toast('Food hidden.');
      }
      _reload();
    } catch (e) {
      _toast('Could not update food: $e');
    }
  }

  Future<void> _deleteOverride(_AdminFoodRow row) async {
    final ok = await _confirm(
      title: 'Delete admin override?',
      message: row.hasBundled
          ? 'This removes the admin version and restores the bundled food data.'
          : 'This removes ${row.entry.displayName} from the admin library.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok) return;

    try {
      await _admin.deleteOverride(row.entry.key);
      _toast('Admin override deleted.');
      _reload();
    } catch (e) {
      _toast('Could not delete override: $e');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: destructive ? Colors.red : _kOrange,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: const Text('Nutrition Admin'),
        actions: [
          IconButton(
            tooltip: 'Refresh library',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _kOrange,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Food'),
      ),
      body: FutureBuilder<_AdminFoodData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _kOrange),
            );
          }

          if (snapshot.hasError) {
            return _AdminErrorState(
              message: 'Could not load food library: ${snapshot.error}',
              onRetry: _reload,
            );
          }

          final data = snapshot.data ?? const _AdminFoodData();
          final rows = _visibleRows(data);

          return RefreshIndicator(
            color: _kOrange,
            onRefresh: () async => _reload(),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                96 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                _buildHeader(theme, data),
                const SizedBox(height: 14),
                _buildSearch(theme),
                const SizedBox(height: 10),
                _buildFilters(data),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  _buildEmpty(theme)
                else
                  ...rows.map(
                    (row) => _AdminFoodCard(
                      row: row,
                      onEdit: () => _openEditor(row),
                      onToggleHidden: () => _toggleHidden(row),
                      onDeleteOverride: row.hasAdmin
                          ? () => _deleteOverride(row)
                          : null,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, _AdminFoodData data) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.restaurant_menu_rounded, color: Colors.white),
          const SizedBox(height: 12),
          const Text(
            'Food Library Control',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add new food, override bundled values, or hide wrong entries.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _HeaderStat(label: 'Total', value: data.rows.length.toString()),
              const SizedBox(width: 10),
              _HeaderStat(label: 'Admin', value: data.adminCount.toString()),
              const SizedBox(width: 10),
              _HeaderStat(label: 'Hidden', value: data.hiddenCount.toString()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearch(ThemeData theme) {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
        hintText: 'Search food, key, or category',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.close, size: 18),
              ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildFilters(_AdminFoodData data) {
    final filters = [
      ('all', 'All', data.rows.length),
      ('admin', 'Admin', data.adminCount),
      ('bundled', 'Bundled', data.bundledOnlyCount),
      ('hidden', 'Hidden', data.hiddenCount),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in filters) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${filter.$2} ${filter.$3}'),
                selected: _filter == filter.$1,
                showCheckmark: false,
                selectedColor: _kOrange,
                labelStyle: TextStyle(
                  color: _filter == filter.$1 ? Colors.white : null,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => setState(() => _filter = filter.$1),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 12),
          Text(
            'No foods found',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try another search or add a new food.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _FoodEditorSheet extends StatefulWidget {
  final FoodEntry? initialEntry;
  final bool isEditingBundledOnly;
  final List<ArchetypeInfo> archetypes;

  const _FoodEditorSheet({
    required this.initialEntry,
    required this.isEditingBundledOnly,
    required this.archetypes,
  });

  @override
  State<_FoodEditorSheet> createState() => _FoodEditorSheetState();
}

class _FoodEditorSheetState extends State<_FoodEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final AdminFoodLibraryService _admin = AdminFoodLibraryService();
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _keyController;
  late final TextEditingController _nameController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _imageUrlController;

  late String _category;
  late String _archetypeId;
  late bool _active;
  bool _saving = false;
  bool _uploadingImage = false;
  bool _keyTouched = false;

  static const _categories = [
    'whole_dish',
    'component',
    'snack',
    'packaged_food',
    'custom',
  ];

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;
    _keyController = TextEditingController(text: entry?.key ?? '');
    _nameController = TextEditingController(text: entry?.displayName ?? '');
    _caloriesController = TextEditingController(
      text: entry == null ? '' : _formatNumber(entry.baseCalories),
    );
    _proteinController = TextEditingController(
      text: entry == null ? '' : _formatNumber(entry.baseProtein),
    );
    _carbsController = TextEditingController(
      text: entry == null ? '' : _formatNumber(entry.baseCarbs),
    );
    _fatController = TextEditingController(
      text: entry == null ? '' : _formatNumber(entry.baseFat),
    );
    _descriptionController = TextEditingController(
      text: entry?.description ?? '',
    );
    _imageUrlController = TextEditingController(text: entry?.imageUrl ?? '');
    _imageUrlController.addListener(_refreshImagePreview);
    _category = _categories.contains(entry?.category)
        ? entry!.category
        : 'component';
    _archetypeId = _initialArchetype(entry);
    _active = entry?.isActive ?? true;
  }

  @override
  void dispose() {
    _imageUrlController.removeListener(_refreshImagePreview);
    _keyController.dispose();
    _nameController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  void _refreshImagePreview() {
    if (mounted) setState(() {});
  }

  String _initialArchetype(FoodEntry? entry) {
    final ids = widget.archetypes.map((archetype) => archetype.archetypeId);
    if (entry != null && ids.contains(entry.archetypeId)) {
      return entry.archetypeId;
    }
    return widget.archetypes.isEmpty
        ? 'generic'
        : widget.archetypes.first.archetypeId;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final imageUrl = _imageUrlController.text.trim();
    final food = FoodEntry(
      key: _keyController.text.trim(),
      displayName: _nameController.text.trim(),
      category: _category,
      baseCalories: double.parse(_caloriesController.text.trim()),
      cookingModifier: 1,
      description: _descriptionController.text.trim(),
      baseProtein: double.tryParse(_proteinController.text.trim()) ?? 0,
      baseCarbs: double.tryParse(_carbsController.text.trim()) ?? 0,
      baseFat: double.tryParse(_fatController.text.trim()) ?? 0,
      archetypeId: _archetypeId,
      imageUrl: imageUrl.isEmpty ? null : imageUrl,
      source: 'admin',
      isActive: _active,
    );

    try {
      await _admin.saveFood(food);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save food: $e')));
    }
  }

  Future<void> _pickAndUploadImage() async {
    if (_uploadingImage || _saving) return;

    var key = _keyController.text.trim();
    if (key.isEmpty && _nameController.text.trim().isNotEmpty) {
      key = _admin.keyFromName(_nameController.text);
      _keyController.text = key;
    }
    if (key.isEmpty || !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(key)) {
      _toast('Enter valid food key first.');
      return;
    }

    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        maxHeight: 1400,
        imageQuality: 86,
        requestFullMetadata: false,
      );
    } catch (e) {
      _toast('Could not open gallery. Check photo permission and try again.');
      return;
    }
    if (picked == null) return;
    if (!mounted) return;

    setState(() => _uploadingImage = true);
    try {
      final url = await _admin.uploadFoodImage(
        imageFile: File(picked.path),
        foodKey: key,
        sourceMimeType: picked.mimeType,
        sourceName: picked.name,
      );
      if (!mounted) return;
      _imageUrlController.text = url;
      _toast('Image uploaded. Tap Save to keep it.');
    } catch (e) {
      if (!mounted) return;
      _toast('Could not upload image. Check Firebase Storage permission.');
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.initialEntry != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.56,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.28,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'Edit Food' : 'Add Food',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (widget.isEditingBundledOnly)
                            Text(
                              'Saving creates an admin override.',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottomInset),
                  children: [
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Food name',
                        prefixIcon: Icon(Icons.restaurant_menu_outlined),
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Enter food name';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        if (isEditing || _keyTouched) return;
                        _keyController.text = _admin.keyFromName(value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _keyController,
                      readOnly: isEditing,
                      decoration: InputDecoration(
                        labelText: 'Food key',
                        helperText: isEditing
                            ? 'Key is locked after creation.'
                            : 'Used by model labels and records.',
                        prefixIcon: const Icon(Icons.key_outlined),
                      ),
                      validator: (value) {
                        final key = (value ?? '').trim();
                        if (key.isEmpty) return 'Enter food key';
                        if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(key)) {
                          return 'Use letters, numbers, underscore only';
                        }
                        return null;
                      },
                      onChanged: (_) => _keyTouched = true,
                    ),
                    const SizedBox(height: 12),
                    _buildCategoryAndPortionFields(),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _caloriesController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Base calories',
                        suffixText: 'kcal',
                        prefixIcon: Icon(Icons.local_fire_department_outlined),
                      ),
                      validator: (value) {
                        final number = double.tryParse((value ?? '').trim());
                        if (number == null || number <= 0) {
                          return 'Enter calories';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildMacroFields(),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descriptionController,
                      minLines: 2,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildImageSection(theme),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: _active,
                      onChanged: (value) => setState(() => _active = value),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      tileColor: theme.colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: theme.dividerColor),
                      ),
                      title: const Text(
                        'Visible in app',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        _active
                            ? 'Users can search and log this food.'
                            : 'Hidden from user food library.',
                      ),
                    ),
                  ],
                ),
              ),
              Container(
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
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving || _uploadingImage ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _kOrange.withValues(alpha: 0.45),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Save Food',
                            style: TextStyle(fontWeight: FontWeight.w900),
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

  Widget _macroField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: 'g'),
    );
  }

  Widget _buildCategoryAndPortionFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Column(
            children: [
              _categoryField(),
              const SizedBox(height: 12),
              _archetypeField(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _categoryField()),
            const SizedBox(width: 10),
            Expanded(child: _archetypeField()),
          ],
        );
      },
    );
  }

  Widget _categoryField() {
    return DropdownButtonFormField<String>(
      initialValue: _category,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Category',
        prefixIcon: Icon(Icons.category_outlined),
      ),
      items: _categories
          .map(
            (category) => DropdownMenuItem(
              value: category,
              child: Text(_label(category), overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) setState(() => _category = value);
      },
    );
  }

  Widget _archetypeField() {
    return DropdownButtonFormField<String>(
      initialValue: _archetypeId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Portion type',
        prefixIcon: Icon(Icons.tune_rounded),
      ),
      items: widget.archetypes
          .map(
            (archetype) => DropdownMenuItem(
              value: archetype.archetypeId,
              child: Text(
                archetype.archetypeLabel,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) setState(() => _archetypeId = value);
      },
    );
  }

  Widget _buildMacroFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fields = [
          _macroField(controller: _proteinController, label: 'Protein'),
          _macroField(controller: _carbsController, label: 'Carbs'),
          _macroField(controller: _fatController, label: 'Fat'),
        ];

        if (constraints.maxWidth < 360) {
          return Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                fields[i],
                if (i != fields.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              Expanded(child: fields[i]),
              if (i != fields.length - 1) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _buildImageSection(ThemeData theme) {
    return Container(
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
            children: [
              const Icon(Icons.image_outlined, color: _kOrange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Food image',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _imageUrlController,
            enabled: !_uploadingImage,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Image URL',
              helperText: 'Upload from phone or paste direct image URL.',
              hintText: 'Google image share links will not load',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final uploadButton = OutlinedButton.icon(
                onPressed: _uploadingImage || _saving
                    ? null
                    : _pickAndUploadImage,
                icon: _uploadingImage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_uploadingImage ? 'Uploading...' : 'Upload image'),
              );
              final clearButton = TextButton.icon(
                onPressed:
                    _uploadingImage || _imageUrlController.text.trim().isEmpty
                    ? null
                    : () => _imageUrlController.clear(),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Clear'),
              );

              if (constraints.maxWidth < 380) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    uploadButton,
                    const SizedBox(height: 6),
                    clearButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: uploadButton),
                  const SizedBox(width: 8),
                  clearButton,
                ],
              );
            },
          ),
          if (_uploadingImage) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(color: _kOrange),
          ],
          const SizedBox(height: 10),
          _ImageUrlPreview(url: _imageUrlController.text.trim()),
          if (_imageUrlController.text.trim().isEmpty)
            Text(
              'Missing image will use the normal food icon fallback.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
}

class _ImageUrlPreview extends StatelessWidget {
  final String url;

  const _ImageUrlPreview({required this.url});

  bool get _looksLikeGoogleShare {
    final lower = url.toLowerCase();
    return lower.contains('share.google') ||
        lower.contains('images.app.goo.gl') ||
        lower.contains('google.com/imgres') ||
        lower.contains('google.com/search');
  }

  bool get _hasSupportedScheme {
    final parsed = Uri.tryParse(url);
    final scheme = parsed?.scheme.toLowerCase();
    return scheme == 'https' || scheme == 'http';
  }

  bool get _looksLikeStoragePath {
    final lower = url.toLowerCase();
    return lower.startsWith('gs://') || lower.startsWith('food_images/');
  }

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    if (_looksLikeStoragePath) {
      return _ImageUrlMessage(
        icon: Icons.cloud_off_rounded,
        color: Colors.orange,
        text:
            'Use the Firebase download URL, not the Storage path. Upload from phone will fill the correct URL automatically.',
      );
    }
    if (!_hasSupportedScheme) {
      return _ImageUrlMessage(
        icon: Icons.error_outline_rounded,
        color: Colors.red,
        text: 'Image URL must start with https:// or http:// to show in Esti.',
      );
    }
    if (_looksLikeGoogleShare) {
      return _ImageUrlMessage(
        icon: Icons.link_off_rounded,
        color: Colors.orange,
        text:
            'This looks like a Google image share/search link. Open the image and copy direct image address instead.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 68,
              height: 68,
              color: _kOrange.withValues(alpha: 0.10),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined, color: _kOrange),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Preview should show here. If it shows broken image, the URL is not a direct image file.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageUrlMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _ImageUrlMessage({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminFoodCard extends StatelessWidget {
  final _AdminFoodRow row;
  final VoidCallback onEdit;
  final VoidCallback onToggleHidden;
  final VoidCallback? onDeleteOverride;

  const _AdminFoodCard({
    required this.row,
    required this.onEdit,
    required this.onToggleHidden,
    required this.onDeleteOverride,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = row.entry;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _FoodImageBox(entry: entry, disabled: row.isHidden),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusChip(row: row),
                        Text(
                          '${_label(entry.category)} / ${_label(entry.archetypeId)}',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _MetricText('${entry.baseCalories.round()} kcal'),
                        _MetricText('P ${entry.baseProtein.round()}g'),
                        _MetricText('C ${entry.baseCarbs.round()}g'),
                        _MetricText('F ${entry.baseFat.round()}g'),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'toggle') onToggleHidden();
                  if (value == 'delete') onDeleteOverride?.call();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(row.isHidden ? 'Restore' : 'Hide'),
                  ),
                  if (onDeleteOverride != null)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete override'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodImageBox extends StatelessWidget {
  final FoodEntry entry;
  final bool disabled;

  const _FoodImageBox({required this.entry, required this.disabled});

  @override
  Widget build(BuildContext context) {
    final color = disabled ? Colors.grey : _kOrange;
    final imageUrl = entry.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 52,
        height: 52,
        color: color.withValues(alpha: 0.12),
        child: imageUrl == null
            ? Icon(Icons.restaurant_menu_rounded, color: color)
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (_, _, _) =>
                    Icon(Icons.broken_image_outlined, color: color),
              ),
      ),
    );
  }
}

class _MetricText extends StatelessWidget {
  final String text;

  const _MetricText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _kOrange,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final _AdminFoodRow row;

  const _StatusChip({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = row.isHidden
        ? Colors.red
        : row.hasAdmin
        ? _kOrange
        : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        row.status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AdminErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _AdminFoodData {
  final Map<String, FoodEntry> bundled;
  final Map<String, FoodEntry> remote;

  const _AdminFoodData({this.bundled = const {}, this.remote = const {}});

  List<_AdminFoodRow> get rows {
    final keys = <String>{...bundled.keys, ...remote.keys}.toList()..sort();
    return [
      for (final key in keys)
        _AdminFoodRow(
          entry: _entryFor(key),
          hasBundled: bundled.containsKey(key),
          hasAdmin: remote.containsKey(key),
        ),
    ]..sort((a, b) => a.entry.displayName.compareTo(b.entry.displayName));
  }

  FoodEntry _entryFor(String key) {
    final remoteEntry = remote[key];
    final bundledEntry = bundled[key];
    if (remoteEntry != null) return remoteEntry;
    return bundledEntry!;
  }

  int get adminCount => rows.where((row) => row.hasAdmin).length;
  int get bundledOnlyCount => rows.where((row) => row.isBundledOnly).length;
  int get hiddenCount => rows.where((row) => row.isHidden).length;
}

class _AdminFoodRow {
  final FoodEntry entry;
  final bool hasBundled;
  final bool hasAdmin;

  const _AdminFoodRow({
    required this.entry,
    required this.hasBundled,
    required this.hasAdmin,
  });

  bool get isHidden => hasAdmin && !entry.isActive;
  bool get isBundledOnly => hasBundled && !hasAdmin;

  String get status {
    if (isHidden) return 'Hidden';
    if (hasAdmin && hasBundled) return 'Override';
    if (hasAdmin) return 'Admin';
    return 'Bundled';
  }
}

String _label(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
