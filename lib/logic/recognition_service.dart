import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:calscan/logic/detection_utils.dart';
import 'package:calscan/logic/food_detection.dart';

class RecognitionService {
  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  List<int>? _inputShape;
  List<int>? _outputShape;
  String? _loadError;

  static const double confidenceThreshold = 0.18;
  static const double iouThreshold = 0.45;
  static const int maxDetections = 12;

  static const List<String> labels = [
    'ABC',
    'Acar_Timun',
    'Apam_Balik',
    'Ayam_Bakar',
    'Ayam_Goreng_Crispy',
    'Ayam_Goreng_Kunyit',
    'Ayam_Kari',
    'Ayam_Masak_Kicap',
    'Ayam_Masak_Kurma',
    'Ayam_Masak_Lemak',
    'Ayam_Masak_Merah',
    'Burger',
    'Cendol',
    'Cek_Mek_Molek',
    'Char_Kway_Teow',
    'Gulai_Ikan_Tongkol',
    'Ikan_Bilis_Goreng',
    'Ikan_Goreng',
    'Kacang_Goreng',
    'Kangkung_Goreng',
    'Karipap',
    'Kaya_Toast',
    'Keli_Goreng',
    'Kentang',
    'Kerabu_Ulam',
    'Keropok_Lekor_keping',
    'Kway_Teow_Goreng',
    'Mee_Goreng',
    'Nasi_Dagang',
    'Nasi_Goreng',
    'Nasi_Kerabu',
    'Nasi_Lemak',
    'Nasi_Minyak',
    'Nasi_Putih',
    'Paru_Goreng',
    'Patin_Tempoyak',
    'Pisang_Goreng',
    'Pizza',
    'Popia_Goreng',
    'Rendang_Daging',
    'Roti_Canai',
    'Sambal',
    'Sambal_Ikan_Bilis',
    'Sambal_Pedas',
    'Satay',
    'Sayur_Goreng',
    'Serunding_kelapa',
    'Solok_Lada',
    'Steak',
    'Telur_Dadar',
    'Telur_Goreng',
    'Telur_Masin',
    'Telur_Rebus',
    'Tempe_Goreng',
    'Timun',
    'Udang',
    'fries',
    'keropok_lekor',
    'kobis',
    'kobis_goreng',
    'sambal_Tumis',
    'tauhu_goreng',
  ];

  bool get isLoaded => _interpreter != null;
  String? get loadError => _loadError;

  Future<void> loadModel() async {
    if (_interpreter != null) return;

    try {
      final interpreter = await Interpreter.fromAsset(
        'lib/assets/best_float32.tflite',
      );
      final isolateInterpreter = await IsolateInterpreter.create(
        address: interpreter.address,
        debugName: 'EstiFoodDetector',
      );
      final inputShape = interpreter.getInputTensor(0).shape;
      final outputShape = interpreter.getOutputTensor(0).shape;

      if (inputShape.length != 4 ||
          inputShape.first != 1 ||
          inputShape.last != 3) {
        interpreter.close();
        throw StateError('Unsupported model input shape: $inputShape');
      }
      if (outputShape.length != 3 || outputShape.first != 1) {
        interpreter.close();
        throw StateError('Unsupported model output shape: $outputShape');
      }

      _interpreter = interpreter;
      _isolateInterpreter = isolateInterpreter;
      _inputShape = inputShape;
      _outputShape = outputShape;
      _loadError = null;
      debugPrint('YOLO model loaded. Input: $inputShape, output: $outputShape');
    } catch (e) {
      _interpreter?.close();
      _interpreter = null;
      _isolateInterpreter = null;
      _loadError = 'Unable to load the food detection model.';
      debugPrint('Error loading YOLO model: $e');
    }
  }

  Future<List<FoodDetection>> recognizeFood(File imageFile) async {
    final interpreter = _interpreter;
    final inputShape = _inputShape;
    final outputShape = _outputShape;
    if (interpreter == null || inputShape == null || outputShape == null) {
      throw StateError(_loadError ?? 'Food detection model is not ready.');
    }

    final decodedImage = img.decodeImage(imageFile.readAsBytesSync());
    if (decodedImage == null) {
      throw const FormatException('The captured image could not be decoded.');
    }

    final inputHeight = inputShape[1];
    final inputWidth = inputShape[2];
    final letterbox = _letterbox(decodedImage, inputWidth, inputHeight);
    final inputBytes = _imageToFloatInput(letterbox.image);
    final input = inputBytes.reshape(inputShape);

    final output = List.generate(
      outputShape[0],
      (_) => List.generate(
        outputShape[1],
        (_) => List<double>.filled(outputShape[2], 0),
      ),
    );
    final isolateInterpreter = _isolateInterpreter;
    if (isolateInterpreter == null) {
      throw StateError('Food detection worker is not ready.');
    }
    await isolateInterpreter.run(input, output);

    debugPrint(
      'YOLO: image=${decodedImage.width}x${decodedImage.height} '
      '→ letterbox scale=${letterbox.scale.toStringAsFixed(4)} '
      'padX=${letterbox.padX} padY=${letterbox.padY}',
    );

    return _parseOutput(
      output,
      outputShape,
      scale: letterbox.scale,
      padX: letterbox.padX,
      padY: letterbox.padY,
      originalWidth: decodedImage.width,
      originalHeight: decodedImage.height,
      inputWidth: inputWidth,
      inputHeight: inputHeight,
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

  List<FoodDetection> _parseOutput(
    List<List<List<double>>> values,
    List<int> shape, {
    required double scale,
    required double padX,
    required double padY,
    required int originalWidth,
    required int originalHeight,
    required int inputWidth,
    required int inputHeight,
  }) {
    return parseYoloDetections(
      values,
      shape,
      labels: labels,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
      maxDetections: maxDetections,
      scale: scale,
      padX: padX,
      padY: padY,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
      inputWidth: inputWidth,
      inputHeight: inputHeight,
    );
  }

  Future<void> close() async {
    await _isolateInterpreter?.close();
    _interpreter?.close();
    _interpreter = null;
    _isolateInterpreter = null;
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
