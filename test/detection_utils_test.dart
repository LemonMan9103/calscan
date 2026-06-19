import 'package:calscan/logic/detection_utils.dart';
import 'package:calscan/logic/food_detection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nonMaximumSuppression', () {
    test('keeps the higher confidence box when overlap is high', () {
      final detections = [
        FoodDetection(
          labelKey: 'Nasi_Lemak',
          confidence: 0.92,
          left: 10,
          top: 10,
          right: 110,
          bottom: 110,
        ),
        FoodDetection(
          labelKey: 'Nasi_Lemak',
          confidence: 0.81,
          left: 18,
          top: 18,
          right: 108,
          bottom: 108,
        ),
      ];

      final result = nonMaximumSuppression(detections, iouThreshold: 0.45);

      expect(result, hasLength(1));
      expect(result.single.confidence, 0.92);
    });

    test('keeps separate boxes when overlap is low', () {
      final detections = [
        FoodDetection(
          labelKey: 'Nasi_Lemak',
          confidence: 0.9,
          left: 0,
          top: 0,
          right: 40,
          bottom: 40,
        ),
        FoodDetection(
          labelKey: 'Ayam_Goreng',
          confidence: 0.8,
          left: 100,
          top: 100,
          right: 140,
          bottom: 140,
        ),
      ];

      final result = nonMaximumSuppression(detections, iouThreshold: 0.45);

      expect(result, hasLength(2));
    });
  });

  group('selectDisplayDetections', () {
    test('prefers the best whole dish over its components', () {
      final detections = [
        FoodDetection(
          labelKey: 'Ayam_Goreng',
          confidence: 0.91,
          left: 0,
          top: 0,
          right: 20,
          bottom: 20,
        ),
        FoodDetection(
          labelKey: 'Nasi_Lemak',
          confidence: 0.83,
          left: 4,
          top: 4,
          right: 24,
          bottom: 24,
        ),
      ];

      final result = selectDisplayDetections(
        detections,
        (label) => label == 'Nasi_Lemak',
      );

      expect(result, hasLength(1));
      expect(result.single.labelKey, 'Nasi_Lemak');
    });

    test('keeps all detections when there is no whole dish', () {
      final detections = [
        FoodDetection(
          labelKey: 'Ayam_Goreng',
          confidence: 0.91,
          left: 0,
          top: 0,
          right: 20,
          bottom: 20,
        ),
        FoodDetection(
          labelKey: 'Telur_Rebus',
          confidence: 0.74,
          left: 30,
          top: 30,
          right: 50,
          bottom: 50,
        ),
      ];

      final result = selectDisplayDetections(detections, (_) => false);

      expect(result, hasLength(2));
      expect(result.map((d) => d.labelKey), ['Ayam_Goreng', 'Telur_Rebus']);
    });
  });

  group('parseYoloDetections', () {
    test('extracts a single detection from channels-first output', () {
      final labels = ['Nasi_Lemak'];
      final values = [
        [
          [50.0],
          [50.0],
          [20.0],
          [20.0],
          [0.95],
        ],
      ];

      final result = parseYoloDetections(
        values,
        [1, 5, 1],
        labels: labels,
        confidenceThreshold: 0.25,
        iouThreshold: 0.45,
        maxDetections: 12,
        scale: 1.0,
        padX: 0,
        padY: 0,
        originalWidth: 200,
        originalHeight: 200,
        inputWidth: 640,
        inputHeight: 640,
      );

      expect(result, hasLength(1));
      expect(result.single.labelKey, 'Nasi_Lemak');
      expect(result.single.left, 40);
      expect(result.single.top, 40);
      expect(result.single.right, 60);
      expect(result.single.bottom, 60);
    });

    test('supports channels-last output with NMS', () {
      final labels = ['Nasi_Lemak', 'Ayam_Goreng'];
      final values = [
        [
          [50.0, 50.0, 20.0, 20.0, 0.9, 0.1],
          [52.0, 52.0, 20.0, 20.0, 0.85, 0.1],
          [150.0, 150.0, 20.0, 20.0, 0.1, 0.95],
        ],
      ];

      final result = parseYoloDetections(
        values,
        [1, 3, 6],
        labels: labels,
        confidenceThreshold: 0.25,
        iouThreshold: 0.45,
        maxDetections: 12,
        scale: 1.0,
        padX: 0,
        padY: 0,
        originalWidth: 300,
        originalHeight: 300,
        inputWidth: 640,
        inputHeight: 640,
      );

      expect(result, hasLength(2));
      expect(
        result.map((detection) => detection.labelKey),
        containsAll(['Nasi_Lemak', 'Ayam_Goreng']),
      );
    });
  });
}
