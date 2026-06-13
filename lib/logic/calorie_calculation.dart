enum Gender { male, female }

class CalorieCalculator {

  //to calculate food calorie by its nutrient
  static double totalCalorie(double protein, double carb, double fat) {
    return protein * 4 + carb * 4 + fat * 9;
  }

  //to calculate base metabolic rate based on biodata
  static double calculateBMR({
    required double weightKg,
    required double heightCm,
    required int age,
    required Gender gender,
  }) {
    double baseBMR = (10 * weightKg) + (6.25 * heightCm) - (5 * age);//standard formula

    if (gender == Gender.male) {
      return baseBMR + 5;
    } else {
      return baseBMR - 161;
    }
  }


  //to calculate suggested intake based on activity
  static double calculateTDEE(double bmr, double activityMultiplier) {
    return bmr * activityMultiplier;
  }


  //to calculate safe deficit based on gender
  static int calculateSafeDeficit(double tdee, Gender gender) {
    const int standardDeficit = 500;
    final int minIntake = (gender == Gender.male) ? 1500 : 1200;

    if (tdee - standardDeficit < minIntake) {
      final int allowedDeficit = (tdee - minIntake).toInt();
      return allowedDeficit.clamp(0, standardDeficit);
    }
    return standardDeficit;
  }

}
