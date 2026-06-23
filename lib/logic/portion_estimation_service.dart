import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class PortionEstimate {
  final String referenceLabel;
  final double referenceArea;
  final double totalFoodArea;
  final double totalFoodRatio;
  final Map<String, double> componentRatios;
  final Map<String, double> componentAreas;

  const PortionEstimate({
    required this.referenceLabel,
    required this.referenceArea,
    required this.totalFoodArea,
    required this.totalFoodRatio,
    required this.componentRatios,
    required this.componentAreas,
  });

  bool get hasUsableRatio => referenceArea > 0 && totalFoodArea > 0;
}

enum PortionSizeSuggestion { small, medium, large, unknown }

class PortionRules {
  static PortionSizeSuggestion classify(double ratio) {
    if (ratio <= 0) return PortionSizeSuggestion.unknown;
    if (ratio < 0.28) return PortionSizeSuggestion.small;
    if (ratio < 0.58) return PortionSizeSuggestion.medium;
    return PortionSizeSuggestion.large;
  }

  static int optionIndexForSuggestion({
    required PortionSizeSuggestion suggestion,
    required List<String> optionLabels,
    required int fallbackIndex,
  }) {
    if (suggestion == PortionSizeSuggestion.unknown) return fallbackIndex;

    final targets = switch (suggestion) {
      PortionSizeSuggestion.small => ['small', 'half', '1 scoop', '1 slice'],
      PortionSizeSuggestion.medium => [
        'regular',
        'medium',
        '1 plate',
        '1 bowl',
        '1 cup',
        '2 slices',
      ],
      PortionSizeSuggestion.large => ['large', '1.5', '3 slices'],
      PortionSizeSuggestion.unknown => <String>[],
    };

    for (var i = 0; i < optionLabels.length; i++) {
      final label = optionLabels[i].toLowerCase();
      if (targets.any(label.contains)) return i;
    }
    return fallbackIndex;
  }
}

class PortionEstimationService {
  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  List<String> _labels = const [];
  List<int>? _inputShape;
  List<int>? _detectionShape;
  List<int>? _prototypeShape;
  String? _loadError;

  static const double confidenceThreshold = 0.20;
  static const double iouThreshold = 0.45;
  static const double maskThreshold = 0.50;
  static const int maxDetections = 20;
  static const int maskCoefficients = 32;
  static const Set<String> referenceLabels = {'plate', 'tapau_box'};

  bool get isLoaded => _interpreter != null;
  String? get loadError => _loadError;

  Future<void> loadModel() async {
    if (_interpreter != null) return;

    try {
      final labelsRaw = await rootBundle.loadString(
        'lib/assets/portion_labels.txt',
      );
      _labels = labelsRaw
          .split(RegExp(r'[\r\n]+'))
          .map((label) => label.trim())
          .where((label) => label.isNotEmpty)
          .toList(growable: false);

      final interpreter = await Interpreter.fromAsset(
        'lib/assets/portion_model_float32.tflite',
      );
      final isolateInterpreter = await IsolateInterpreter.create(
        address: interpreter.address,
        debugName: 'EstiPortionSegmenter',
      );

      final inputShape = interpreter.getInputTensor(0).shape;
      final detectionShape = interpreter.getOutputTensor(0).shape;
      final prototypeShape = interpreter.getOutputTensor(1).shape;

      if (inputShape.length != 4 ||
          inputShape.first != 1 ||
          inputShape.last != 3) {
        interpreter.close();
        throw StateError('Unsupported portion input shape: $inputShape');
      }
      if (detectionShape.length != 3 || detectionShape.first != 1) {
        interpreter.close();
        throw StateError('Unsupported portion output shape: $detectionShape');
      }
      if (prototypeShape.length != 4 ||
          prototypeShape.first != 1 ||
          prototypeShape.last != maskCoefficients) {
        interpreter.close();
        throw StateError('Unsupported portion mask shape: $prototypeShape');
      }

      _interpreter = interpreter;
      _isolateInterpreter = isolateInterpreter;
      _inputShape = inputShape;
      _detectionShape = detectionShape;
      _prototypeShape = prototypeShape;
      _loadError = null;

      debugPrint(
        'Portion model loaded. Input: $inputShape, outputs: '
        '$detectionShape / $prototypeShape',
      );
    } catch (e) {
      _interpreter?.close();
      _interpreter = null;
      _isolateInterpreter = null;
      _loadError = 'Unable to load portion model.';
      debugPrint('Error loading portion model: $e');
    }
  }

  Future<PortionEstimate?> estimate(File imageFile) async {
    final inputShape = _inputShape;
    final detectionShape = _detectionShape;
    final prototypeShape = _prototypeShape;
    final isolateInterpreter = _isolateInterpreter;
    if (inputShape == null ||
        detectionShape == null ||
        prototypeShape == null ||
        isolateInterpreter == null) {
      throw StateError(_loadError ?? 'Portion model is not ready.');
    }

    final decoded = img.decodeImage(imageFile.readAsBytesSync());
    if (decoded == null) {
      throw const FormatException('The captured image could not be decoded.');
    }

    final inputHeight = inputShape[1];
    final inputWidth = inputShape[2];
    final letterbox = _letterbox(decoded, inputWidth, inputHeight);
    final input = _imageToFloatInput(letterbox.image).reshape(inputShape);

    final detections = List.generate(
      detectionShape[0],
      (_) => List.generate(
        detectionShape[1],
        (_) => List<double>.filled(detectionShape[2], 0),
      ),
    );
    final prototypes = List.generate(
      prototypeShape[0],
      (_) => List.generate(
        prototypeShape[1],
        (_) => List.generate(
          prototypeShape[2],
          (_) => List<double>.filled(prototypeShape[3], 0),
        ),
      ),
    );

    await isolateInterpreter.runForMultipleInputs(
      [input],
      {0: detections, 1: prototypes},
    );

    final parsed = _parseDetections(
      detections,
      detectionShape,
      inputWidth: inputWidth,
      inputHeight: inputHeight,
      protoWidth: prototypeShape[2],
      protoHeight: prototypeShape[1],
    );
    final kept = _nonMaxSuppression(parsed);
    if (kept.isEmpty) return null;

    return _buildEstimate(
      detections: kept,
      prototypes: prototypes[0],
      protoWidth: prototypeShape[2],
      protoHeight: prototypeShape[1],
    );
  }

  PortionEstimate? _buildEstimate({
    required List<_SegmentDetection> detections,
    required List<List<List<double>>> prototypes,
    required int protoWidth,
    required int protoHeight,
  }) {
    final masks = <_SegmentMask>[];
    for (final detection in detections) {
      masks.add(
        _buildMask(
          detection: detection,
          prototypes: prototypes,
          protoWidth: protoWidth,
          protoHeight: protoHeight,
        ),
      );
    }

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

  _SegmentMask _buildMask({
    required _SegmentDetection detection,
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

    return _SegmentMask(
      label: detection.label,
      width: protoWidth,
      height: protoHeight,
      pixels: pixels,
      area: area.toDouble(),
    );
  }

  List<_SegmentDetection> _parseDetections(
    List<List<List<double>>> values,
    List<int> shape, {
    required int inputWidth,
    required int inputHeight,
    required int protoWidth,
    required int protoHeight,
  }) {
    final attrs = shape[1];
    final anchors = shape[2];
    final classCount = _labels.length;
    final expectedWithoutObjectness = 4 + classCount + maskCoefficients;
    final expectedWithObjectness = 5 + classCount + maskCoefficients;
    final hasObjectness = attrs == expectedWithObjectness;
    if (attrs != expectedWithoutObjectness && attrs != expectedWithObjectness) {
      throw StateError(
        'Unsupported portion attributes: $attrs. Labels=$classCount',
      );
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

    final classStart = hasObjectness ? 5 : 4;
    final maskStart = classStart + classCount;
    final detections = <_SegmentDetection>[];

    for (var anchor = 0; anchor < anchors; anchor++) {
      var bestClass = -1;
      var bestScore = 0.0;
      for (var classIndex = 0; classIndex < classCount; classIndex++) {
        final score = valueAt(anchor, classStart + classIndex);
        if (score > bestScore) {
          bestScore = score;
          bestClass = classIndex;
        }
      }
      if (bestClass == -1) continue;

      final objectness = hasObjectness ? valueAt(anchor, 4) : 1.0;
      final confidence = objectness * bestScore;
      if (confidence < confidenceThreshold) continue;

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
        _SegmentDetection(
          label: _labels[bestClass],
          confidence: confidence,
          left: (cx - w / 2).clamp(0.0, protoWidth.toDouble()),
          top: (cy - h / 2).clamp(0.0, protoHeight.toDouble()),
          right: (cx + w / 2).clamp(0.0, protoWidth.toDouble()),
          bottom: (cy + h / 2).clamp(0.0, protoHeight.toDouble()),
          maskCoefficients: coefficients,
        ),
      );
    }

    debugPrint(
      'Portion YOLO: candidates=${detections.length}, normalized=$normalizedCoords',
    );
    return detections;
  }

  List<_SegmentDetection> _nonMaxSuppression(
    List<_SegmentDetection> detections,
  ) {
    final candidates = List<_SegmentDetection>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final selected = <_SegmentDetection>[];

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

  double _iou(_SegmentDetection a, _SegmentDetection b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    final intersection =
        math.max(0.0, right - left) * math.max(0.0, bottom - top);
    final union = a.area + b.area - intersection;
    return union <= 0 ? 0 : intersection / union;
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

  Future<void> close() async {
    await _isolateInterpreter?.close();
    _interpreter?.close();
    _interpreter = null;
    _isolateInterpreter = null;
  }
}

class _SegmentDetection {
  final String label;
  final double confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final List<double> maskCoefficients;

  const _SegmentDetection({
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

class _SegmentMask {
  final String label;
  final int width;
  final int height;
  final Uint8List pixels;
  final double area;

  const _SegmentMask({
    required this.label,
    required this.width,
    required this.height,
    required this.pixels,
    required this.area,
  });

  double overlapArea(_SegmentMask other) {
    final length = math.min(pixels.length, other.pixels.length);
    var count = 0;
    for (var i = 0; i < length; i++) {
      if (pixels[i] == 1 && other.pixels[i] == 1) count++;
    }
    return count.toDouble();
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
