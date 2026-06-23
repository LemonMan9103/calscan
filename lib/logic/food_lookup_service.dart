import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A single selectable portion option for a chips-type archetype.
class PortionOption {
  final String label;
  final double multiplier;
  const PortionOption({required this.label, required this.multiplier});
}

/// The portion configuration for a food archetype.
/// [inputType] is either 'chips' or 'counter'.
class ArchetypeInfo {
  final String archetypeId;
  final String archetypeLabel;
  final String inputType;

  // chips fields
  final List<PortionOption> options;
  final int defaultIndex;

  // counter fields
  final String unitName;
  final String unitNamePlural;
  final int referenceCount;
  final int minCount;
  final int defaultCount;

  const ArchetypeInfo({
    required this.archetypeId,
    required this.archetypeLabel,
    required this.inputType,
    this.options = const [],
    this.defaultIndex = 0,
    this.unitName = '',
    this.unitNamePlural = '',
    this.referenceCount = 1,
    this.minCount = 1,
    this.defaultCount = 1,
  });

  bool get isCounter => inputType == 'counter';

  PortionOption option(int index) => options.isEmpty
      ? const PortionOption(label: 'Regular', multiplier: 1.0)
      : options[index.clamp(0, options.length - 1)];

  PortionOption get defaultOption => option(defaultIndex);

  String countLabel(int count) =>
      '$count ${count == 1 ? unitName : unitNamePlural}';
}

/// Holds all data for a single food entry from the lookup table.
class FoodEntry {
  final String key;
  final String displayName;
  final String category;
  final double baseCalories;
  final double cookingModifier;
  final String description;
  final double baseProtein;
  final double baseCarbs;
  final double baseFat;
  final String archetypeId;
  final String? imageUrl;
  final String source;
  final bool isActive;

  const FoodEntry({
    required this.key,
    required this.displayName,
    required this.category,
    required this.baseCalories,
    required this.cookingModifier,
    required this.description,
    required this.baseProtein,
    required this.baseCarbs,
    required this.baseFat,
    required this.archetypeId,
    this.imageUrl,
    this.source = 'bundled',
    this.isActive = true,
  });

  factory FoodEntry.fromMap(
    String key,
    Map<String, dynamic> data, {
    String source = 'admin',
  }) {
    double readDouble(String snake, [String? camel]) {
      final value = data[snake] ?? (camel == null ? null : data[camel]);
      return (value as num?)?.toDouble() ?? 0.0;
    }

    String readString(String snake, [String? camel]) {
      final value = data[snake] ?? (camel == null ? null : data[camel]);
      return value?.toString() ?? '';
    }

    final fallbackName = key.replaceAll('_', ' ');
    final name = readString('display_name', 'displayName').trim();

    return FoodEntry(
      key: key,
      displayName: name.isEmpty ? fallbackName : name,
      category: readString('category').isEmpty
          ? 'component'
          : readString('category'),
      baseCalories: readDouble('base_calories', 'baseCalories'),
      cookingModifier: readDouble('cooking_modifier', 'cookingModifier'),
      description: readString('description'),
      baseProtein: readDouble('protein_g', 'protein'),
      baseCarbs: readDouble('carbs_g', 'carbs'),
      baseFat: readDouble('fat_g', 'fat'),
      archetypeId: readString('archetype', 'archetypeId').isEmpty
          ? 'generic'
          : readString('archetype', 'archetypeId'),
      imageUrl: readString('image_url', 'imageUrl').trim().isEmpty
          ? null
          : readString('image_url', 'imageUrl').trim(),
      source: source,
      isActive: data['active'] != false,
    );
  }

  Map<String, dynamic> toAdminMap() {
    return {
      'display_name': displayName,
      'category': category,
      'base_calories': baseCalories,
      'cooking_modifier': cookingModifier,
      'description': description,
      'protein_g': baseProtein,
      'carbs_g': baseCarbs,
      'fat_g': baseFat,
      'archetype': archetypeId,
      'image_url': imageUrl ?? '',
      'active': isActive,
      'source': source,
    };
  }

  FoodEntry copyWith({
    String? key,
    String? displayName,
    String? category,
    double? baseCalories,
    double? cookingModifier,
    String? description,
    double? baseProtein,
    double? baseCarbs,
    double? baseFat,
    String? archetypeId,
    String? imageUrl,
    String? source,
    bool? isActive,
  }) {
    return FoodEntry(
      key: key ?? this.key,
      displayName: displayName ?? this.displayName,
      category: category ?? this.category,
      baseCalories: baseCalories ?? this.baseCalories,
      cookingModifier: cookingModifier ?? this.cookingModifier,
      description: description ?? this.description,
      baseProtein: baseProtein ?? this.baseProtein,
      baseCarbs: baseCarbs ?? this.baseCarbs,
      baseFat: baseFat ?? this.baseFat,
      archetypeId: archetypeId ?? this.archetypeId,
      imageUrl: imageUrl ?? this.imageUrl,
      source: source ?? this.source,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Singleton service — loads `food_lookup.json` once and provides lookups.
class FoodLookupService {
  static final FoodLookupService _instance = FoodLookupService._internal();
  factory FoodLookupService() => _instance;
  FoodLookupService._internal();

  bool _loaded = false;
  final Map<String, FoodEntry> _entries = {};
  final Map<String, FoodEntry> _localEntries = {};
  final Map<String, ArchetypeInfo> _archetypes = {};

  static final ArchetypeInfo _fallback = ArchetypeInfo(
    archetypeId: 'generic',
    archetypeLabel: 'Serving',
    inputType: 'chips',
    options: const [
      PortionOption(label: 'Small', multiplier: 0.8),
      PortionOption(label: 'Regular', multiplier: 1.0),
      PortionOption(label: 'Large', multiplier: 1.3),
    ],
    defaultIndex: 1,
  );

  Future<void> load() async {
    if (_loaded) return;

    final raw = await rootBundle.loadString('lib/assets/food_lookup.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final meta = json['metadata'] as Map<String, dynamic>;

    final archetypeMap = meta['archetypes'] as Map<String, dynamic>? ?? {};
    for (final entry in archetypeMap.entries) {
      final d = entry.value as Map<String, dynamic>;
      final inputType = d['input_type'] as String? ?? 'chips';

      List<PortionOption> options = [];
      int defaultIndex = 0;
      String unitName = '';
      String unitNamePlural = '';
      int referenceCount = 1;
      int minCount = 1;
      int defaultCount = 1;

      if (inputType == 'chips') {
        final rawOpts = d['options'] as List<dynamic>? ?? [];
        options = rawOpts.map((o) {
          final opt = o as Map<String, dynamic>;
          return PortionOption(
            label: opt['label'] as String,
            multiplier: (opt['multiplier'] as num).toDouble(),
          );
        }).toList();
        defaultIndex = (d['default'] as num?)?.toInt() ?? 0;
      } else {
        unitName = d['unit_name'] as String? ?? '';
        unitNamePlural = d['unit_name_plural'] as String? ?? '';
        referenceCount = (d['reference_count'] as num?)?.toInt() ?? 1;
        minCount = (d['min_count'] as num?)?.toInt() ?? 1;
        defaultCount = (d['default_count'] as num?)?.toInt() ?? 1;
      }

      _archetypes[entry.key] = ArchetypeInfo(
        archetypeId: entry.key,
        archetypeLabel: d['label'] as String? ?? entry.key,
        inputType: inputType,
        options: options,
        defaultIndex: defaultIndex,
        unitName: unitName,
        unitNamePlural: unitNamePlural,
        referenceCount: referenceCount,
        minCount: minCount,
        defaultCount: defaultCount,
      );
    }

    final foods = json['foods'] as Map<String, dynamic>;
    for (final entry in foods.entries) {
      final d = entry.value as Map<String, dynamic>;
      final food = FoodEntry(
        key: entry.key,
        displayName: d['display_name'] as String,
        category: d['category'] as String,
        baseCalories: (d['base_calories'] as num).toDouble(),
        cookingModifier: (d['cooking_modifier'] as num).toDouble(),
        description: d['description'] as String,
        baseProtein: (d['protein_g'] as num?)?.toDouble() ?? 0.0,
        baseCarbs: (d['carbs_g'] as num?)?.toDouble() ?? 0.0,
        baseFat: (d['fat_g'] as num?)?.toDouble() ?? 0.0,
        archetypeId: d['archetype'] as String? ?? 'generic',
      );
      _localEntries[entry.key] = food;
      _entries[entry.key] = food;
    }

    _loaded = true;
  }

  Future<void> refreshRemoteEntries() async {
    await load();

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('food_library')
          .get();

      _entries
        ..clear()
        ..addAll(_localEntries);

      for (final doc in snapshot.docs) {
        final entry = FoodEntry.fromMap(doc.id, doc.data(), source: 'admin');
        if (!entry.isActive) {
          // admin can hide bundled food by same key
          _entries.remove(doc.id);
          continue;
        }
        _entries[doc.id] = entry;
      }
    } catch (e) {
      debugPrint('Food library remote refresh failed: $e');
    }
  }

  // ── Lookups ─────────────────────────────────────────────────────────────────

  FoodEntry? lookup(String key) => _entries[key];
  String getDisplayName(String key) =>
      _entries[key]?.displayName ?? key.replaceAll('_', ' ');
  String getCategory(String key) => _entries[key]?.category ?? '';
  String getDescription(String key) => _entries[key]?.description ?? '';

  // ── Archetype ───────────────────────────────────────────────────────────────

  ArchetypeInfo getArchetype(String labelKey) {
    final id = _entries[labelKey]?.archetypeId;
    if (id == null) return _fallback;
    return _archetypes[id] ?? _fallback;
  }

  int getDefaultPortionIndex(String labelKey) =>
      getArchetype(labelKey).defaultIndex;

  // ── Calorie & macro calculation — chips type ─────────────────────────────────

  double getCaloriesForOption(String labelKey, int optionIndex) {
    final entry = _entries[labelKey];
    if (entry == null) return 0.0;
    return entry.baseCalories *
        getArchetype(labelKey).option(optionIndex).multiplier;
  }

  ({double protein, double carbs, double fat}) getMacrosForOption(
    String labelKey,
    int optionIndex,
  ) {
    final entry = _entries[labelKey];
    if (entry == null) return (protein: 0.0, carbs: 0.0, fat: 0.0);
    final m = getArchetype(labelKey).option(optionIndex).multiplier;
    return (
      protein: entry.baseProtein * m,
      carbs: entry.baseCarbs * m,
      fat: entry.baseFat * m,
    );
  }

  // ── Calorie & macro calculation — counter type ───────────────────────────────

  double getCaloriesForCount(String labelKey, int count) {
    final entry = _entries[labelKey];
    if (entry == null) return 0.0;
    final arch = getArchetype(labelKey);
    return entry.baseCalories * count / arch.referenceCount;
  }

  ({double protein, double carbs, double fat}) getMacrosForCount(
    String labelKey,
    int count,
  ) {
    final entry = _entries[labelKey];
    if (entry == null) return (protein: 0.0, carbs: 0.0, fat: 0.0);
    final ratio = count / getArchetype(labelKey).referenceCount;
    return (
      protein: entry.baseProtein * ratio,
      carbs: entry.baseCarbs * ratio,
      fat: entry.baseFat * ratio,
    );
  }

  // ── Convenience ─────────────────────────────────────────────────────────────

  Iterable<FoodEntry> get allEntries => _entries.values;
  Iterable<FoodEntry> get bundledEntries => _localEntries.values;
  Iterable<ArchetypeInfo> get allArchetypes => _archetypes.values;
  bool get isLoaded => _loaded;
}
