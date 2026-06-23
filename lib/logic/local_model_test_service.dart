import 'dart:io';
import 'dart:math' as math;

import 'package:calscan/logic/detection_utils.dart';
import 'package:calscan/logic/food_detection.dart';
import 'package:calscan/logic/portion_estimation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class LocalDetectionTestResult {
  final List<int> inputShape;
  final List<int> outputShape;
  final List<String> labels;
  final List<FoodDetection> detections;

  const LocalDetectionTestResult({
    required this.inputShape,
    required this.outputShape,
    required this.labels,
    required this.detections,
  });
}

class LocalPortionTestResult {
  final List<int> inputShape;
  final List<int> detectionShape;
  final List<int> prototypeShape;
  final List<String> labels;
  final PortionEstimate? estimate;

  const LocalPortionTestResult({
    required this.inputShape,
    required this.detectionShape,
    required this.prototypeShape,
    required this.labels,
    required this.estimate,
  });
}

class LocalModelTestService {
  static const double detectionConfidenceThreshold = 0.18;
  static const double portionConfidenceThreshold = 0.20;
  static const double iouThreshold = 0.45;
  static const double maskThreshold = 0.50;
  static const int maxDetections = 20;
  static const int maskCoefficients = 32;
  static const Set<String> referenceLabels = {'plate', 'tapau_box'};

  Future<LocalDetectionTestResult> testDetection({
    required File modelFile,
    required File labelsFile,
    required File imageFile,
  }) async {
    final labels = await _readLabels(labelsFile);
    final interpreter = Interpreter.fromFile(modelFile);
    try {
      final inputShape = interpreter.getInputTensor(0).shape;
      final outputShape = interpreter.getOutputTensor(0).shape;
      _checkYoloInputShape(inputShape, 'detection');

      final decoded = _readImage(imageFile);
      final inputHeight = inputShape[1];
      final inputWidth = inputShape[2];
      final letterbox = _letterbox(decoded, inputWidth, inputHeight);
      final input = _imageToFloatInput(letterbox.image).reshape(inputShape);
      final output = _empty3d(outputShape);

      interpreter.run(input, output);

      final detections = parseYoloDetections(
        output,
        outputShape,
        labels: labels,
        confidenceThreshold: detectionConfidenceThreshold,
        iouThreshold: iouThreshold,
        maxDetections: 12,
        scale: letterbox.scale,
        padX: letterbox.padX,
        padY: letterbox.padY,
        originalWidth: decoded.width,
        originalHeight: decoded.height,
        inputWidth: inputWidth,
        inputHeight: inputHeight,
      );

      return LocalDetectionTestResult(
        inputShape: inputShape,
        outputShape: outputShape,
        labels: labels,
        detections: detections,
      );
    } finally {
      interpreter.close();
    }
  }

  Future<LocalPortionTestResult> testPortion({
    required File modelFile,
    required File labelsFile,
    required File imageFile,
  }) async {
    final labels = await _readLabels(labelsFile);
    final interpreter = Interpreter.fromFile(modelFile);
    try {
      final inputShape = interpreter.getInputTensor(0).shape;
      final detectionShape = interpreter.getOutputTensor(0).shape;
      final prototypeShape = interpreter.getOutputTensor(1).shape;
      _checkYoloInputShape(inputShape, 'portion');
      _checkPortionShapes(detectionShape, prototypeShape, labels.length);

      final decoded = _readImage(imageFile);
      final inputHeight = inputShape[1];
      final inputWidth = inputShape[2];
      final letterbox = _letterbox(decoded, inputWidth, inputHeight);
      final input = _imageToFloatInput(letterbox.image).reshape(inputShape);
      final detections = _empty3d(detectionShape);
      final prototypes = _empty4d(prototypeShape);

      interpreter.runForMultipleInputs([input], {0: detections, 1: prototypes});

      final parsed = _parsePortionDetections(
        detections,
        detectionShape,
        labels: labels,
        inputWidth: inputWidth,
        inputHeight: inputHeight,
        protoWidth: prototypeShape[2],
        protoHeight: prototypeShape[1],
      );
      final kept = _portionNms(parsed);
      final estimate = kept.isEmpty
          ? null
          : _buildPortionEstimate(
              detections: kept,
              prototypes: prototypes[0],
              protoWidth: prototypeShape[2],
              protoHeight: prototypeShape[1],
            );

      return LocalPortionTestResult(
        inputShape: inputShape,
        detectionShape: detectionShape,
        prototypeShape: prototypeShape,
        labels: labels,
        estimate: estimate,
      );
    } finally {
      interpreter.close();
    }
  }

  Future<List<String>> _readLabels(File file) async {
    final labels = await file.readAsLines().then(
      (lines) => lines
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false),
    );
    if (labels.isEmpty) {
      throw const FormatException('Labels file is empty.');
    }
    return labels;
  }

  void _checkYoloInputShape(List<int> inputShape, String modelType) {
    if (inputShape.length != 4 ||
        inputShape.first != 1 ||
        inputShape.last != 3) {
      throw StateError('Unsupported $modelType input shape: $inputShape');
    }
  }

  void _checkPortionShapes(
    List<int> detectionShape,
    List<int> prototypeShape,
    int labelCount,
  ) {
    if (detectionShape.length != 3 || detectionShape.first != 1) {
      throw StateError('Unsupported portion detection shape: $detectionShape');
    }
    if (prototypeShape.length != 4 ||
        prototypeShape.first != 1 ||
        prototypeShape.last != maskCoefficients) {
      throw StateError('Unsupported portion mask shape: $prototypeShape');
    }
    final attrs = detectionShape[1];
    final expectedWithoutObjectness = 4 + labelCount + maskCoefficients;
    final expectedWithObjectness = 5 + labelCount + maskCoefficients;
    if (attrs != expectedWithoutObjectness && attrs != expectedWithObjectness) {
      throw StateError(
        'Portion labels do not match model output. '
        'Attributes=$attrs, labels=$labelCount.',
      );
    }
  }

  img.Image _readImage(File imageFile) {
    final decoded = img.decodeImage(imageFile.readAsBytesSync());
    if (decoded == null) {
      throw const FormatException('The selected image could not be decoded.');
    }
    return decoded;
  }

  List<List<List<double>>> _empty3d(List<int> shape) {
    return List.generate(
      shape[0],
      (_) => List.generate(shape[1], (_) => List<double>.filled(shape[2], 0)),
    );
  }

  List<List<List<List<double>>>> _empty4d(List<int> shape) {
    return List.generate(
      shape[0],
      (_) => List.generate(
        shape[1],
        (_) => List.generate(shape[2], (_) => List<double>.filled(shape[3], 0)),
      ),
    );
  }

  _LetterboxResult _letterbox(
    img.Image source,
    int targetWidth,
    int targetHeight,
  ) {
    final scale = math.min(
      targetWidth / source.width,
      targetHeight / source.height,
    );
    final resizedWidth = math.max(1, (source.width * scale).round()).toInt();
    final resizedHeight = math.max(1, (source.height * scale).round()).toInt();
    final resized = img.copyResize(
      source,
      width: resizedWidth,
      height: resizedHeight,
      interpolation: img.Interpolation.linear,
    );
    final canvas = img.Image(
      width: targetWidth,
      height: targetHeight,
      numChannels: 3,
    );
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
    final padX = ((targetWidth - resizedWidth) / 2).floor();
    final padY = ((targetHeight - resizedHeight) / 2).floor();
    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

    return _LetterboxResult(
      image: canvas,
      scale: scale,
      padX: padX.toDouble(),
      padY: padY.toDouble(),
    );
  }

  Float32List _imageToFloatInput(img.Image image) {
    final input = Float32List(image.width * image.height * 3);
    var index = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        input[index++] = pixel.r / 255.0;
        input[index++] = pixel.g / 255.0;
        input[index++] = pixel.b / 255.0;
      }
    }
    return input;
  }

  List<_LocalSegmentDetection> _parsePortionDetections(
    List<List<List<double>>> values,
    List<int> shape, {
    required List<String> labels,
    required int inputWidth,
    required int inputHeight,
    required int protoWidth,
    required int protoHeight,
  }) {
    final attrs = shape[1];
    final anchors = shape[2];
    final expectedWithoutObjectness = 4 + labels.length + maskCoefficients;
    final expectedWithObjectness = 5 + labels.length + maskCoefficients;
    final hasObjectness = attrs == expectedWithObjectness;
    if (attrs != expectedWithoutObjectness && attrs != expectedWithObjectness) {
      throw StateError('Unsupported portion attributes: $attrs');
    }

    double valueAt(int anchor, int attr) => values[0][attr][anchor];

    var maxCoord = 0.0;
    final sampleCount = anchors < 300 ? anchors : 300;
    for (var anchor = 0; anchor < sampleCount; anchor++) {
      for (var attr = 0; attr < 4; attr++) {
        final value = valueAt(anchor, attr).abs();
        if (value > maxCoord) maxCoord = value;
      }
    }
    final normalizedCoords = maxCoord < 2.0;
    debugPrint(
      'Local portion test: sampled max bbox coord=$maxCoord, '
      'normalized=$normalizedCoords',
    );

    final classStart = hasObjectness ? 5 : 4;
    final maskStart = classStart + labels.length;
    final detections = <_LocalSegmentDetection>[];

    for (var anchor = 0; anchor < anchors; anchor++) {
      var bestClass = -1;
      var bestScore = 0.0;
      for (var classIndex = 0; classIndex < labels.length; classIndex++) {
        final score = valueAt(anchor, classStart + classIndex);
        if (score > bestScore) {
          bestScore = score;
          bestClass = classIndex;
        }
      }
      if (bestClass == -1) continue;

      final objectness = hasObjectness ? valueAt(anchor, 4) : 1.0;
      final confidence = objectness * bestScore;
      if (confidence < portionConfidenceThreshold) continue;

      final rawCx = valueAt(anchor, 0);
      final rawCy = valueAt(anchor, 1);
      final rawW = valueAt(anchor, 2);
      final rawH = valueAt(anchor, 3);

      final cx = normalizedCoords
          ? rawCx * protoWidth
          : rawCx / inputWidth * protoWidth;
      final cy = normalizedCoords
          ? rawCy * protoHeight
          : rawCy / inputHeight * protoHeight;
      final w = normalizedCoords
          ? rawW * protoWidth
          : rawW / inputWidth * protoWidth;
      final h = normalizedCoords
          ? rawH * protoHeight
          : rawH / inputHeight * protoHeight;

      final coefficients = List<double>.generate(
        maskCoefficients,
        (index) => valueAt(anchor, maskStart + index),
        growable: false,
      );

      detections.add(
        _LocalSegmentDetection(
          label: labels[bestClass],
          confidence: confidence,
          left: (cx - w / 2).clamp(0.0, protoWidth.toDouble()),
          top: (cy - h / 2).clamp(0.0, protoHeight.toDouble()),
          right: (cx + w / 2).clamp(0.0, protoWidth.toDouble()),
          bottom: (cy + h / 2).clamp(0.0, protoHeight.toDouble()),
          maskCoefficients: coefficients,
        ),
      );
    }

    return detections;
  }

  List<_LocalSegmentDetection> _portionNms(
    List<_LocalSegmentDetection> detections,
  ) {
    final candidates = List<_LocalSegmentDetection>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final selected = <_LocalSegmentDetection>[];

    for (final candidate in candidates) {
      final overlaps = selected.any(
        (kept) =>
            kept.label == candidate.label &&
            _iou(kept, candidate) > iouThreshold,
      );
      if (!overlaps) selected.add(candidate);
      if (selected.length >= maxDetections) break;
    }
    return selected;
  }

  PortionEstimate? _buildPortionEstimate({
    required List<_LocalSegmentDetection> detections,
    required List<List<List<double>>> prototypes,
    required int protoWidth,
    required int protoHeight,
  }) {
    final masks = <_LocalSegmentMask>[
      for (final detection in detections)
        _buildMask(
          detection: detection,
          prototypes: prototypes,
          protoWidth: protoWidth,
          protoHeight: protoHeight,
        ),
    ];

    final references =
        masks
            .where((mask) => referenceLabels.contains(mask.label))
            .where((mask) => mask.area > 0)
            .toList()
          ..sort((a, b) => b.area.compareTo(a.area));
    if (references.isEmpty) return null;

    final reference = references.first;
    final componentAreas = <String, double>{};

    for (final mask in masks) {
      if (referenceLabels.contains(mask.label)) continue;
      final overlapArea = mask.overlapArea(reference);
      if (overlapArea <= 0) continue;
      componentAreas.update(
        mask.label,
        (value) => value + overlapArea,
        ifAbsent: () => overlapArea,
      );
    }

    final totalFoodArea = componentAreas.values.fold<double>(
      0,
      (total, area) => total + area,
    );
    final componentRatios = {
      for (final entry in componentAreas.entries)
        entry.key: entry.value / reference.area,
    };

    return PortionEstimate(
      referenceLabel: reference.label,
      referenceArea: reference.area,
      totalFoodArea: totalFoodArea,
      totalFoodRatio: totalFoodArea / reference.area,
      componentAreas: componentAreas,
      componentRatios: componentRatios,
    );
  }

  _LocalSegmentMask _buildMask({
    required _LocalSegmentDetection detection,
    required List<List<List<double>>> prototypes,
    required int protoWidth,
    required int protoHeight,
  }) {
    final pixels = Uint8List(protoWidth * protoHeight);
    final left = detection.left.floor().clamp(0, protoWidth - 1);
    final top = detection.top.floor().clamp(0, protoHeight - 1);
    final right = detection.right.ceil().clamp(0, protoWidth);
    final bottom = detection.bottom.ceil().clamp(0, protoHeight);
    var area = 0;

    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        var logit = 0.0;
        for (var k = 0; k < maskCoefficients; k++) {
          logit += detection.maskCoefficients[k] * prototypes[y][x][k];
        }
        final probability = 1 / (1 + math.exp(-logit));
        if (probability >= maskThreshold) {
          pixels[y * protoWidth + x] = 1;
          area++;
        }
      }
    }

    return _LocalSegmentMask(
      label: detection.label,
      pixels: pixels,
      area: area.toDouble(),
    );
  }

  double _iou(_LocalSegmentDetection a, _LocalSegmentDetection b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    final intersection =
        math.max(0.0, right - left) * math.max(0.0, bottom - top);
    final union = a.area + b.area - intersection;
    return union <= 0 ? 0 : intersection / union;
  }
}

class _LetterboxResult {
  final img.Image image;
  final double scale;
  final double padX;
  final double padY;

  const _LetterboxResult({
    required this.image,
    required this.scale,
    required this.padX,
    required this.padY,
  });
}

class _LocalSegmentDetection {
  final String label;
  final double confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final List<double> maskCoefficients;

  const _LocalSegmentDetection({
    required this.label,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.maskCoefficients,
  });

  double get area => math.max(0.0, right - left) * math.max(0.0, bottom - top);
}

class _LocalSegmentMask {
  final String label;
  final Uint8List pixels;
  final double area;

  const _LocalSegmentMask({
    required this.label,
    required this.pixels,
    required this.area,
  });

  double overlapArea(_LocalSegmentMask other) {
    final length = math.min(pixels.length, other.pixels.length);
    var count = 0;
    for (var i = 0; i < length; i++) {
      if (pixels[i] == 1 && other.pixels[i] == 1) count++;
    }
    return count.toDouble();
  }
}
