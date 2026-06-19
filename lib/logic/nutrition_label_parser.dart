enum CalorieBasis { perServing, perPackage, per100g, unknown }

extension CalorieBasisLabel on CalorieBasis {
  String get label {
    switch (this) {
      case CalorieBasis.perServing:
        return 'Per serving';
      case CalorieBasis.perPackage:
        return 'Per package';
      case CalorieBasis.per100g:
        return 'Per 100 g';
      case CalorieBasis.unknown:
        return 'Not sure';
    }
  }
}

class NutritionLabelEstimate {
  final String productName;
  final double? calories;
  final double? caloriesPer100g;
  final double? servingSize;
  final double? servingsPerPackage;
  final CalorieBasis calorieBasis;
  final String serving;
  final String rawText;

  const NutritionLabelEstimate({
    required this.productName,
    required this.calories,
    this.caloriesPer100g,
    this.servingSize,
    this.servingsPerPackage,
    required this.calorieBasis,
    required this.serving,
    required this.rawText,
  });
}

NutritionLabelEstimate parseNutritionLabel(String rawText) {
  final lines = rawText
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final calorieResult = _findCalories(lines);
  final per100gResult = _findBasisCalories(lines, CalorieBasis.per100g);
  final servingSize = _findServingSize(lines);
  final servingsPerPackage = _findServingsPerPackage(lines);

  return NutritionLabelEstimate(
    productName: _findProductName(lines),
    calories: calorieResult.calories,
    caloriesPer100g: per100gResult?.calories,
    servingSize: servingSize,
    servingsPerPackage: servingsPerPackage,
    calorieBasis: calorieResult.basis,
    serving: _findServing(lines),
    rawText: rawText.trim(),
  );
}

_CalorieResult _findCalories(List<String> lines) {
  final serving = _findBasisCalories(lines, CalorieBasis.perServing);
  if (serving != null) return serving;

  final package = _findBasisCalories(lines, CalorieBasis.perPackage);
  if (package != null) return package;

  final per100g = _findBasisCalories(lines, CalorieBasis.per100g);
  if (per100g != null) return per100g;

  final calorieLine = RegExp(
    r'\bcalories?\b\s*[:\-]?\s*(\d{1,4}(?:[.,]\d+)?)',
    caseSensitive: false,
  );
  final kcalValue = RegExp(
    r'(\d{1,4}(?:[.,]\d+)?)\s*kcal\b',
    caseSensitive: false,
  );
  final plainNumber = RegExp(r'^\s*(\d{1,4}(?:[.,]\d+)?)\s*$');

  for (var index = 0; index < lines.length; index++) {
    final direct = calorieLine.firstMatch(lines[index]);
    if (direct != null) {
      return _CalorieResult(
        calories: _parseNumber(direct.group(1)),
        basis: CalorieBasis.perServing,
      );
    }

    if (lines[index].toLowerCase().contains('calor') &&
        index + 1 < lines.length) {
      final next = plainNumber.firstMatch(lines[index + 1]);
      if (next != null) {
        return _CalorieResult(
          calories: _parseNumber(next.group(1)),
          basis: CalorieBasis.perServing,
        );
      }
    }
  }

  for (final line in lines) {
    final match = kcalValue.firstMatch(line);
    if (match != null) {
      return _CalorieResult(
        calories: _parseNumber(match.group(1)),
        basis: CalorieBasis.unknown,
      );
    }
  }

  final kilojoule = RegExp(
    r'(\d{2,5}(?:[.,]\d+)?)\s*kj\b',
    caseSensitive: false,
  );
  for (final line in lines) {
    final match = kilojoule.firstMatch(line);
    final value = _parseNumber(match?.group(1));
    if (value != null) {
      return _CalorieResult(
        calories: value / 4.184,
        basis: CalorieBasis.unknown,
      );
    }
  }

  return const _CalorieResult(calories: null, basis: CalorieBasis.unknown);
}

_CalorieResult? _findBasisCalories(List<String> lines, CalorieBasis basis) {
  final basisPattern = switch (basis) {
    CalorieBasis.perServing => RegExp(
      r'\bper serving\b|\beach serving\b|\bserving contains\b',
      caseSensitive: false,
    ),
    CalorieBasis.perPackage => RegExp(
      r'\bper package\b|\bper pack\b|\bper container\b|\bwhole pack\b',
      caseSensitive: false,
    ),
    CalorieBasis.per100g => RegExp(
      r'\bper\s*100\s*g\b|\b100\s*g\b',
      caseSensitive: false,
    ),
    CalorieBasis.unknown => RegExp(r'$.'),
  };
  final valuePattern = RegExp(
    r'(\d{1,4}(?:[.,]\d+)?)\s*kcal\b',
    caseSensitive: false,
  );

  for (var index = 0; index < lines.length; index++) {
    if (!basisPattern.hasMatch(lines[index])) continue;

    final sameLine = valuePattern.allMatches(lines[index]).toList();
    if (sameLine.isNotEmpty) {
      return _CalorieResult(
        calories: _parseNumber(sameLine.last.group(1)),
        basis: basis,
      );
    }

    for (var offset = 1; offset <= 3; offset++) {
      final nextIndex = index + offset;
      if (nextIndex >= lines.length) break;
      final values = valuePattern.allMatches(lines[nextIndex]).toList();
      if (values.isEmpty) continue;

      // Tables often list "per 100 g" first and "per serving" second.
      final match = basis == CalorieBasis.perServing && values.length > 1
          ? values.last
          : values.first;
      return _CalorieResult(
        calories: _parseNumber(match.group(1)),
        basis: basis,
      );
    }
  }
  return null;
}

String _findServing(List<String> lines) {
  for (final line in lines) {
    if (RegExp(
      r'\bserving size\b|\bper serving\b|\bservings per\b',
      caseSensitive: false,
    ).hasMatch(line)) {
      return line;
    }
  }
  return '1 serving';
}

double? _findServingSize(List<String> lines) {
  final labeledServingSize = RegExp(r'\bserving size\b', caseSensitive: false);
  final measuredValue = RegExp(
    r'(\d{1,5}(?:[.,]\d+)?)\s*(?:g|gram|grams|ml|mL)\b',
    caseSensitive: false,
  );
  final fallbackNumber = RegExp(r'(\d{1,5}(?:[.,]\d+)?)');

  for (final line in lines) {
    final lower = line.toLowerCase();
    if (lower.contains('servings per')) continue;
    if (!labeledServingSize.hasMatch(line)) continue;

    // get real grams/ml, not "1" from "1 bar (40g)"
    final measured = measuredValue.allMatches(line).toList();
    if (measured.isNotEmpty) {
      final value = _parseNumber(measured.last.group(1));
      if (value != null) return value;
    }

    final fallback = fallbackNumber.firstMatch(line);
    final value = _parseNumber(fallback?.group(1));
    if (value != null) return value;
  }

  return null;
}

double? _findServingsPerPackage(List<String> lines) {
  final patterns = [
    RegExp(
      r'\bservings?\s+per\s+(?:package|pack|container)\b[^0-9]*(\d{1,3}(?:[.,]\d+)?)',
      caseSensitive: false,
    ),
    RegExp(
      r'\babout\s+(\d{1,3}(?:[.,]\d+)?)\s+servings?\b',
      caseSensitive: false,
    ),
  ];

  for (final line in lines) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(line);
      final value = _parseNumber(match?.group(1));
      if (value != null) return value;
    }
  }

  return null;
}

String _findProductName(List<String> lines) {
  const excludedTerms = [
    'nutrition',
    'calorie',
    'energy',
    'serving',
    'protein',
    'carbohydrate',
    'total fat',
    'saturated',
    'sodium',
    'sugar',
    'ingredient',
    'daily value',
    'vitamin',
    'cholesterol',
    'per 100',
  ];

  for (final line in lines.take(10)) {
    final lower = line.toLowerCase();
    if (excludedTerms.any(lower.contains)) continue;
    if (line.length < 2 || line.length > 60) continue;
    if (RegExp(r'\d').allMatches(line).length > 2) continue;
    if (!RegExp(r'[A-Za-z]').hasMatch(line)) continue;
    return line;
  }

  return '';
}

double? _parseNumber(String? value) {
  if (value == null) return null;
  return double.tryParse(value.replaceAll(',', '.'));
}

class _CalorieResult {
  final double? calories;
  final CalorieBasis basis;

  const _CalorieResult({required this.calories, required this.basis});
}
