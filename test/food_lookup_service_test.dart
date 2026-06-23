import 'package:calscan/logic/food_lookup_service.dart';
import 'package:calscan/logic/recognition_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled food lookup covers every recognition label', () async {
    final lookup = FoodLookupService();
    await lookup.load();

    final missing = [
      for (final label in RecognitionService.labels)
        if (lookup.lookup(label) == null) label,
    ];

    expect(missing, isEmpty);
  });

  test('bundled food lookup does not keep unavailable model classes', () async {
    final lookup = FoodLookupService();
    await lookup.load();

    final recognitionLabels = RecognitionService.labels.toSet();
    final staleFoods = [
      for (final food in lookup.bundledEntries)
        if (!recognitionLabels.contains(food.key)) food.key,
    ];

    expect(staleFoods, isEmpty);
  });
}
