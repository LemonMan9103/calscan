import 'dart:convert';
import 'package:flutter/services.dart';

/// Portion size options.
enum PortionSize { small, medium, large }

extension PortionSizeExt on PortionSize {
  String get label {
    switch (this) {
      case PortionSize.small:
        return 'Small';
      case PortionSize.medium:
        return 'Medium';
      case PortionSize.large:
        return 'Large';
    }
  }

  String get key {
    switch (this) {
      case PortionSize.small:
        return 'S';
      case PortionSize.medium:
        return 'M';
      case PortionSize.large:
        return 'L';
    }
  }
}

/// Holds all data for a single food entry from the lookup table.
class FoodEntry {
  final String key;
  final String displayName;
  final String category;
  final double baseCalories;
  final double cookingModifier;
  final String description;

  const FoodEntry({
    required this.key,
    required this.displayName,
    required this.category,
    required this.baseCalories,
    required this.cookingModifier,
    required this.description,
  });

  /// Final calories = base_calories × portion_multiplier
  double calories(PortionSize portion, Map<String, double> multipliers) {
    final multiplier = multipliers[portion.key] ?? 1.0;
    return baseCalories * multiplier;
  }
}

/// Singleton service that loads `food_lookup.json` once and provides lookups.
class FoodLookupService {
  static final FoodLookupService _instance = FoodLookupService._internal();
  factory FoodLookupService() => _instance;
  FoodLookupService._internal();

  bool _loaded = false;
  final Map<String, FoodEntry> _entries = {};
  Map<String, double> _portionMultipliers = {'S': 0.8, 'M': 1.0, 'L': 1.3};

  /// Call once (e.g. in main() or initState). Safe to call multiple times.
  Future<void> load() async {
    if (_loaded) return;

    final raw = await rootBundle.loadString('lib/assets/food_lookup.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;

    // Parse portion multipliers from metadata
    final meta = json['metadata'] as Map<String, dynamic>;
    final pm = meta['portion_multipliers'] as Map<String, dynamic>;
    _portionMultipliers = pm.map((k, v) => MapEntry(k, (v as num).toDouble()));

    // Parse food entries
    final foods = json['foods'] as Map<String, dynamic>;
    for (final entry in foods.entries) {
      final data = entry.value as Map<String, dynamic>;
      _entries[entry.key] = FoodEntry(
        key: entry.key,
        displayName: data['display_name'] as String,
        category: data['category'] as String,
        baseCalories: (data['base_calories'] as num).toDouble(),
        cookingModifier: (data['cooking_modifier'] as num).toDouble(),
        description: data['description'] as String,
      );
    }

    _loaded = true;
  }

  /// Get a [FoodEntry] by its underscore key (e.g. `'Nasi_Lemak'`).
  /// Returns null if not found or not yet loaded.
  FoodEntry? lookup(String key) => _entries[key];

  /// Compute final calories for a food + portion combination.
  ///
  /// [labelKey] — underscore key matching model labels (e.g. `'Ayam_Goreng'`)
  /// [portion]  — S / M / L
  ///
  /// Returns 0 if the food key is unknown.
  double getCalories(String labelKey, PortionSize portion) {
    final entry = _entries[labelKey];
    if (entry == null) return 0.0;
    return entry.calories(portion, _portionMultipliers);
  }

  /// Human-readable display name (spaces instead of underscores).
  String getDisplayName(String labelKey) {
    return _entries[labelKey]?.displayName ??
        labelKey.replaceAll('_', ' ');
  }

  /// Food category (e.g. `'whole_dish'`, `'component'`, `'snack'`).
  String getCategory(String labelKey) {
    return _entries[labelKey]?.category ?? '';
  }

  /// Short description of the food.
  String getDescription(String labelKey) {
    return _entries[labelKey]?.description ?? '';
  }

  Map<String, double> get portionMultipliers => Map.unmodifiable(_portionMultipliers);
  bool get isLoaded => _loaded;
}
