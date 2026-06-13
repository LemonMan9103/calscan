import 'package:calscan/logic/calorie_calculation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calculates calories from macronutrients', () {
    expect(CalorieCalculator.totalCalorie(10, 20, 5), 165);
  });

  test('keeps a calorie deficit above the safe minimum', () {
    expect(CalorieCalculator.calculateSafeDeficit(1700, Gender.male), 200);
  });
}
