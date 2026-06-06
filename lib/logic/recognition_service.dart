import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class RecognitionService {
  Interpreter? _interpreter;
  List<String>? _labels;

  // Configuration for panels to note (Change based on your model's requirement)
  static const int inputSize = 224; 
  
  // Example labels - for real deployment, use your labels.txt
  final List<String> _defaultLabels = [
    'Apple', 'Banana', 'Burger', 'Cake', 'Egg', 'Noodles', 'Pizza', 'Rice', 'Salad', 'Steak'
  ];

  Future<void> loadModel() async {
    try {
      // Step 1: Load the Engine (Interpreter)
      _interpreter = await Interpreter.fromAsset('lib/assets/food_detection.tflite');
      _labels = _defaultLabels; // Ideally load from assets/labels.txt
      debugPrint('Model loaded successfully');
    } catch (e) {
      debugPrint('Error loading model: $e');
    }
  }

  // Pure logic for panels: Input(Pixels) -> Model -> Output(Confidence Score)
  Map<String, dynamic>? recognizeFood(File imageFile) {
    if (_interpreter == null) return null;

    // 1. Preprocessing: Resize and Convert to list of pixels (floats)
    final imageBytes = imageFile.readAsBytesSync();
    final decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) return null;

    final resizedImage = img.copyResize(decodedImage, width: inputSize, height: inputSize);
    
    // Convert to Float32 list for the model [1, 224, 224, 3]
    var input = List.generate(1, (i) => List.generate(inputSize, (j) => List.generate(inputSize, (k) => List<double>.filled(3, 0.0))));
    
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resizedImage.getPixel(x, y);
        input[0][y][x][0] = pixel.r / 255.0; // Red
        input[0][y][x][1] = pixel.g / 255.0; // Green
        input[0][y][x][2] = pixel.b / 255.0; // Blue
      }
    }

    // 2. Inference: Run the math through the neural network
    // output shape usually matches number of classes [1, 10]
    var output = List.filled(1 * _labels!.length, 0.0).reshape([1, _labels!.length]);
    
    _interpreter!.run(input, output);

    // 3. Post-processing: Find the index with the highest confidence
    List<double> results = List<double>.from(output[0]);
    double maxScore = -1;
    int maxIndex = -1;

    for (int i = 0; i < results.length; i++) {
      if (results[i] > maxScore) {
        maxScore = results[i];
        maxIndex = i;
      }
    }

    // Returning the "Winner"
    if (maxIndex != -1) {
      return {
        'label': _labels![maxIndex],
        'confidence': maxScore,
        'calories': _lookupCalories(_labels![maxIndex]),
      };
    }
    
    return null;
  }

  // Simple hardcoded mapping for the demo
  double _lookupCalories(String label) {
    switch (label) {
      case 'Apple': return 95;
      case 'Banana': return 105;
      case 'Burger': return 350;
      case 'Cake': return 250;
      case 'Egg': return 70;
      case 'Noodles': return 220;
      case 'Pizza': return 285;
      case 'Rice': return 130;
      case 'Salad': return 40;
      case 'Steak': return 670;
      default: return 0;
    }
  }

  void close() {
    _interpreter?.close();
  }
}
