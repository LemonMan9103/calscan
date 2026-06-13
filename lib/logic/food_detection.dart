import 'dart:math' as math;

class FoodDetection {
  final String labelKey;
  final double confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const FoodDetection({
    required this.labelKey,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get area => math.max(0.0, right - left) * math.max(0.0, bottom - top);
}
