import 'package:calscan/logic/portion_estimation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PortionRules', () {
    test('classifies mask ratio into portion size', () {
      expect(PortionRules.classify(0), PortionSizeSuggestion.unknown);
      expect(PortionRules.classify(0.20), PortionSizeSuggestion.small);
      expect(PortionRules.classify(0.40), PortionSizeSuggestion.medium);
      expect(PortionRules.classify(0.70), PortionSizeSuggestion.large);
    });

    test('maps suggested size to matching chip label', () {
      final labels = ['Half plate', '1 plate', 'Large plate'];

      expect(
        PortionRules.optionIndexForSuggestion(
          suggestion: PortionSizeSuggestion.small,
          optionLabels: labels,
          fallbackIndex: 1,
        ),
        0,
      );
      expect(
        PortionRules.optionIndexForSuggestion(
          suggestion: PortionSizeSuggestion.medium,
          optionLabels: labels,
          fallbackIndex: 0,
        ),
        1,
      );
      expect(
        PortionRules.optionIndexForSuggestion(
          suggestion: PortionSizeSuggestion.large,
          optionLabels: labels,
          fallbackIndex: 0,
        ),
        2,
      );
    });
  });
}
