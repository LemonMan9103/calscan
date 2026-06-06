import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class RecognitionService {
  Interpreter? _interpreter;

  // YOLO input resolution (must match training config)
  static const int inputSize = 640;

  // Confidence threshold — detections below this are ignored
  static const double confidenceThreshold = 0.25;

  // 49 Malaysian food classes from data.yaml (order matters — matches model output indices)
  static const List<String> labels = [
    'Apam_Balik',
    'Ayam_Bakar',
    'Ayam_Goreng',
    'Ayam_Goreng_Kunyit',
    'Ayam_Masak_Kicap',
    'Ayam_Masak_Kurma',
    'Ayam_Masak_Lemak',
    'Ayam_Masak_Merah',
    'Burger',
    'Cendol',
    'Char_Kway_Teow',
    'Daging_Bakar',
    'Gulai_Ikan_Tongkol',
    'Ikan_Bilis_Goreng',
    'Ikan_Goreng',
    'Kacang_Goreng',
    'Kangkung_Goreng',
    'Karipap',
    'Kaya_Toast',
    'Keli_Goreng',
    'Kentang',
    'Kway_Teow_Goreng',
    'Mee_Goreng',
    'Nasi_Dagang',
    'Nasi_Goreng',
    'Nasi_Hujan_Panas',
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
    'Satay',
    'Solok_Lada',
    'Steak',
    'Telur_Dadar',
    'Telur_Goreng',
    'Telur_Masin',
    'Telur_Rebus',
    'Tempe_Goreng',
    'Timun',
    'Udang',
  ];



  /// Load the YOLO TFLite interpreter from assets.
  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'lib/assets/best_float32.tflite',
      );
      debugPrint('YOLO model loaded. Input: ${_interpreter!.getInputTensors()}');
      debugPrint('Output tensors: ${_interpreter!.getOutputTensors()}');
    } catch (e) {
      debugPrint('Error loading YOLO model: $e');
    }
  }

  /// Run inference on [imageFile].
  ///
  /// Returns a map with keys:
  ///   - `labelKey`   : raw underscore key matching food_lookup.json (e.g. `'Nasi_Lemak'`)
  ///   - `confidence` : float 0–1
  ///
  /// Calorie calculation is done externally via [FoodLookupService] so the
  /// caller can apply the user-selected portion multiplier.
  ///
  /// Returns `null` if no detection passes the confidence threshold.
  Map<String, dynamic>? recognizeFood(File imageFile) {
    if (_interpreter == null) {
      debugPrint('Interpreter not loaded.');
      return null;
    }

    // ── 1. Preprocessing ────────────────────────────────────────────────────
    final imageBytes = imageFile.readAsBytesSync();
    final decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) return null;

    final resized = img.copyResize(
      decodedImage,
      width: inputSize,
      height: inputSize,
    );

    // Build [1, 640, 640, 3] Float32 tensor (normalised 0–1)
    final input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
          },
        ),
      ),
    );

    // ── 2. Inference ─────────────────────────────────────────────────────────
    // YOLOv8 float32 output: [1, num_classes + 4, num_anchors]
    //   num_classes = 49, so rows = 53 (4 box coords + 49 scores)
    //   num_anchors = 8400 for 640-input
    const int numRows = 53; // 4 + 49
    const int numAnchors = 8400;

    // tflite_flutter needs a pre-allocated output buffer
    var output = List.generate(
      1,
      (_) => List.generate(numRows, (_) => List<double>.filled(numAnchors, 0.0)),
    );

    try {
      _interpreter!.run(input, output);
    } catch (e) {
      debugPrint('Inference error: $e');
      return null;
    }

    // ── 3. Post-processing ───────────────────────────────────────────────────
    // YOLOv8 layout: rows 0–3 = cx,cy,w,h; rows 4–52 = class scores per anchor
    final rawOut = output[0]; // shape [53][8400]

    double bestScore = -1;
    int bestClass = -1;

    for (int a = 0; a < numAnchors; a++) {
      // Find the class with the highest score for this anchor
      double maxClassScore = -1;
      int maxClassIdx = -1;

      for (int c = 0; c < labels.length; c++) {
        final score = rawOut[4 + c][a];
        if (score > maxClassScore) {
          maxClassScore = score;
          maxClassIdx = c;
        }
      }

      if (maxClassScore > bestScore) {
        bestScore = maxClassScore;
        bestClass = maxClassIdx;
      }
    }

    if (bestScore < confidenceThreshold || bestClass == -1) {
      debugPrint('No detection above threshold (best: $bestScore)');
      return null;
    }

    final label = labels[bestClass];
    debugPrint('Detected: $label (score: ${bestScore.toStringAsFixed(3)})');

    return {
      'labelKey': label,          // raw key for FoodLookupService
      'confidence': bestScore,
    };
  }

  void close() {
    _interpreter?.close();
  }
}
