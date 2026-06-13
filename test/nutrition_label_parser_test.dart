import 'package:calscan/logic/nutrition_label_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts product name, calories, and serving', () {
    final result = parseNutritionLabel('''
Chocolate Oat Bar
Nutrition Facts
Serving size 1 bar (40g)
Calories 180
Total Fat 7g
''');

    expect(result.productName, 'Chocolate Oat Bar');
    expect(result.calories, 180);
    expect(result.calorieBasis, CalorieBasis.perServing);
    expect(result.serving, 'Serving size 1 bar (40g)');
  });

  test('prefers kcal when energy also includes kilojoules', () {
    final result = parseNutritionLabel('''
Energy
840 kJ / 200 kcal
Protein 4g
''');

    expect(result.calories, 200);
  });

  test('prefers per-serving value over per-100g table value', () {
    final result = parseNutritionLabel('''
Per 100g Per serving
Energy 1880 kJ / 450 kcal 1340 kJ / 320 kcal
''');

    expect(result.calories, 320);
    expect(result.calorieBasis, CalorieBasis.perServing);
  });

  test('marks a per-100g-only value correctly', () {
    final result = parseNutritionLabel('''
Average nutrition information per 100g
Energy 1880 kJ / 450 kcal
''');

    expect(result.calories, 450);
    expect(result.calorieBasis, CalorieBasis.per100g);
  });

  test('converts kilojoules when kcal is unavailable', () {
    final result = parseNutritionLabel('Energy 418.4 kJ');

    expect(result.calories, closeTo(100, 0.1));
  });
}
