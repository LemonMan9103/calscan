import 'package:flutter/foundation.dart';
import 'package:calscan/logic/food_detection.dart';

List<FoodDetection> nonMaximumSuppression(
  List<FoodDetection> detections, {
  double iouThreshold = 0.45,
  int maxDetections = 12,
}) {
  final candidates = List<FoodDetection>.from(detections)
    ..sort((a, b) => b.confidence.compareTo(a.confidence));

  final selected = <FoodDetection>[];
  for (final candidate in candidates) {
    final overlaps = selected.any(
      (kept) =>
          kept.labelKey == candidate.labelKey &&
          intersectionOverUnion(kept, candidate) > iouThreshold,
    );
    if (!overlaps) selected.add(candidate);
    if (selected.length >= maxDetections) break;
  }
  return selected;
}

List<FoodDetection> parseYoloDetections(
  List<List<List<double>>> values,
  List<int> shape, {
  required List<String> labels,
  required double confidenceThreshold,
  required double iouThreshold,
  required int maxDetections,
  required double scale,
  required double padX,
  required double padY,
  required int originalWidth,
  required int originalHeight,
  required int inputWidth,
  required int inputHeight,
}) {
  final expectedAttributes = labels.length + 4;
  final isChannelsFirst = shape[1] == expectedAttributes;
  final isChannelsLast = shape[2] == expectedAttributes;
  if (!isChannelsFirst && !isChannelsLast) {
    throw StateError(
      'Unsupported model output shape $shape. '
      'Expected one dimension to equal $expectedAttributes '
      '(${labels.length} classes + 4 bbox coords).',
    );
  }

  final anchors = isChannelsFirst ? shape[2] : shape[1];
  double valueAt(int anchor, int attribute) =>
      isChannelsFirst ? values[0][attribute][anchor] : values[0][anchor][attribute];

  // Auto-detect coordinate space: sample bbox values and check if all are ≤ ~2.
  // Absolute coords from a 640-input model have many values >> 1.
  // Normalized (0–1) coords stay well below 2.
  bool coordinatesAreNormalized() {
    var maxCoord = 0.0;
    final sampleCount = anchors < 300 ? anchors : 300;
    for (var a = 0; a < sampleCount; a++) {
      for (var ch = 0; ch < 4; ch++) {
        final v = valueAt(a, ch).abs();
        if (v > maxCoord) maxCoord = v;
      }
    }
    final isNorm = maxCoord < 2.0;
    debugPrint('YOLO: sampled max bbox coord=$maxCoord → ${isNorm ? "normalized" : "absolute"} coords');
    return isNorm;
  }

  final coordinatesNormalized = coordinatesAreNormalized();

  var totalAboveThreshold = 0;
  final candidates = <FoodDetection>[];

  for (var anchor = 0; anchor < anchors; anchor++) {
    var bestClass = -1;
    var bestScore = 0.0;
    for (var classIndex = 0; classIndex < labels.length; classIndex++) {
      final score = valueAt(anchor, classIndex + 4);
      if (score > bestScore) {
        bestScore = score;
        bestClass = classIndex;
      }
    }
    if (bestClass == -1 || bestScore < confidenceThreshold) continue;
    totalAboveThreshold++;

    // Convert to canvas pixel space, then unpad to original image coordinates
    final rawCx = valueAt(anchor, 0);
    final rawCy = valueAt(anchor, 1);
    final rawW = valueAt(anchor, 2);
    final rawH = valueAt(anchor, 3);

    final cx = coordinatesNormalized ? rawCx * inputWidth : rawCx;
    final cy = coordinatesNormalized ? rawCy * inputHeight : rawCy;
    final w = coordinatesNormalized ? rawW * inputWidth : rawW;
    final h = coordinatesNormalized ? rawH * inputHeight : rawH;

    final left = ((cx - w / 2) - padX) / scale;
    final top = ((cy - h / 2) - padY) / scale;
    final right = ((cx + w / 2) - padX) / scale;
    final bottom = ((cy + h / 2) - padY) / scale;

    final detection = FoodDetection(
      labelKey: labels[bestClass],
      confidence: bestScore,
      left: left.clamp(0.0, originalWidth.toDouble()),
      top: top.clamp(0.0, originalHeight.toDouble()),
      right: right.clamp(0.0, originalWidth.toDouble()),
      bottom: bottom.clamp(0.0, originalHeight.toDouble()),
    );
    if (detection.area > 1) candidates.add(detection);
  }

  debugPrint(
    'YOLO: anchors=$anchors, above-threshold=$totalAboveThreshold, '
    'valid-boxes=${candidates.length}',
  );

  return nonMaximumSuppression(
    candidates,
    iouThreshold: iouThreshold,
    maxDetections: maxDetections,
  );
}

List<FoodDetection> selectDisplayDetections(
  List<FoodDetection> detections,
  bool Function(String labelKey) isWholeDish,
) {
  if (detections.isEmpty) return const [];

  final wholeDishes =
      detections.where((detection) => isWholeDish(detection.labelKey)).toList()
        ..sort((a, b) => b.confidence.compareTo(a.confidence));

  if (wholeDishes.isNotEmpty) return [wholeDishes.first];
  return List.unmodifiable(detections);
}

double intersectionOverUnion(FoodDetection a, FoodDetection b) {
  final intersectionLeft = a.left > b.left ? a.left : b.left;
  final intersectionTop = a.top > b.top ? a.top : b.top;
  final intersectionRight = a.right < b.right ? a.right : b.right;
  final intersectionBottom = a.bottom < b.bottom ? a.bottom : b.bottom;

  final intersectionWidth = (intersectionRight - intersectionLeft).clamp(
    0.0,
    double.infinity,
  );
  final intersectionHeight = (intersectionBottom - intersectionTop).clamp(
    0.0,
    double.infinity,
  );
  final intersectionArea = intersectionWidth * intersectionHeight;
  final unionArea = a.area + b.area - intersectionArea;
  return unionArea <= 0 ? 0 : intersectionArea / unionArea;
}
