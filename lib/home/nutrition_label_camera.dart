import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:calscan/logic/nutrition_label_parser.dart';
import 'package:calscan/logic/crud_records.dart';
import 'package:calscan/logic/offline_write.dart';

const _kOrange = Color(0xFFFF7E00);

/// Full-screen camera that captures a nutrition label, runs OCR, and routes
/// to a confirmation page where the user names the food and saves it.
class NutritionLabelCameraPage extends StatefulWidget {
  const NutritionLabelCameraPage({super.key});

  @override
  State<NutritionLabelCameraPage> createState() =>
      _NutritionLabelCameraPageState();
}

class _NutritionLabelCameraPageState extends State<NutritionLabelCameraPage> {
  CameraController? _controller;
  final TextRecognizer _recognizer = TextRecognizer();
  bool _isProcessing = false;
  bool _isInitializing = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _errorMessage = null;
      });
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera was found on this device.');
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() => _isInitializing = false);
    } on CameraException catch (e) {
      _setError(e.description ?? 'The camera could not be initialized.');
    } catch (e) {
      _setError(e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _isInitializing = false;
      _errorMessage = message;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    unawaited(_recognizer.close());
    super.dispose();
  }

  Future<void> _handleCapture() async {
    final controller = _controller;
    if (_isProcessing ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    try {
      setState(() => _isProcessing = true);
      final image = await controller.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final recognized = await _recognizer.processImage(inputImage);
      final estimate = parseNutritionLabel(recognized.text);

      if (mounted) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => _NutritionLabelResultPage(
              imageFile: File(image.path),
              estimate: estimate,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read label: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) return _buildErrorState();
    if (_isInitializing || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: _kOrange),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),
          _buildScanFrame(),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back,
                    color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _isProcessing
                      ? 'Reading label…'
                      : 'Align the nutrition panel in the frame',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _isProcessing ? null : _handleCapture,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: _kOrange, width: 4),
                    ),
                    child: _isProcessing
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(
                              color: _kOrange,
                              strokeWidth: 3,
                            ),
                          )
                        : const Icon(Icons.document_scanner,
                            color: _kOrange, size: 32),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanFrame() {
    return Center(
      child: Container(
        width: 280,
        height: 360,
        decoration: BoxDecoration(
          border: Border.all(color: _kOrange, width: 3),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white54, size: 56),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _initialize,
                style: ElevatedButton.styleFrom(backgroundColor: _kOrange),
                child: const Text('Retry',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Result / confirmation page ─────────────────────────────────────────────────

class _NutritionLabelResultPage extends StatefulWidget {
  final File imageFile;
  final NutritionLabelEstimate estimate;

  const _NutritionLabelResultPage({
    required this.imageFile,
    required this.estimate,
  });

  @override
  State<_NutritionLabelResultPage> createState() =>
      _NutritionLabelResultPageState();
}

class _NutritionLabelResultPageState extends State<_NutritionLabelResultPage> {
  final RecordService _records = RecordService();

  late final TextEditingController _nameController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _servingController;
  late final TextEditingController _weightController;

  DateTime _timestamp = DateTime.now();
  bool _saving = false;
  bool _showRawText = false;
  // Whether calories were last set by the weight calculator (vs manual entry).
  bool _calFromWeight = false;

  @override
  void initState() {
    super.initState();
    final est = widget.estimate;
    _nameController = TextEditingController();
    _caloriesController = TextEditingController(
      text: est.calories == null ? '' : est.calories!.round().toString(),
    );
    _servingController = TextEditingController(text: est.serving);
    _weightController = TextEditingController();
    _weightController.addListener(_onWeightChanged);
  }

  void _onWeightChanged() {
    final per100g = widget.estimate.caloriesPer100g;
    if (per100g == null || per100g <= 0) return;
    final grams = double.tryParse(_weightController.text);
    if (grams == null || grams <= 0) {
      // User cleared the weight — restore original per-serving value.
      if (_calFromWeight) {
        final original = widget.estimate.calories;
        _caloriesController.text =
            original == null ? '' : original.round().toString();
        _calFromWeight = false;
      }
      return;
    }
    final computed = (grams / 100.0) * per100g;
    _calFromWeight = true;
    _caloriesController.text = computed.round().toString();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _servingController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _timestamp,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_timestamp),
    );
    if (!mounted) return;
    setState(() {
      _timestamp = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _timestamp.hour,
        time?.minute ?? _timestamp.minute,
      );
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final calories = double.tryParse(_caloriesController.text.trim());

    if (name.isEmpty) {
      _toast('Please enter a food name.');
      return;
    }
    if (calories == null || calories <= 0) {
      _toast('Please enter a valid calorie value.');
      return;
    }

    setState(() => _saving = true);

    // Build a serving description that includes weight when the user entered one.
    final weightGrams = double.tryParse(_weightController.text.trim());
    final servingDesc = weightGrams != null && weightGrams > 0
        ? '${weightGrams.toStringAsFixed(0)} g'
        : _servingController.text.trim();

    final mealData = <String, dynamic>{
      'mealName': name,
      'calories': calories.round(),
      'items': [
        {
          'key': null,
          'name': name,
          'calories': calories.roundToDouble(),
          'serving': servingDesc,
          'isCustom': true,
        }
      ],
      'serving': servingDesc,
      'timestamp': Timestamp.fromDate(_timestamp),
      'source': 'label_ocr',
    };

    try {
      final status = await _records.addMeal(mealData);
      if (!mounted) return;
      Navigator.pop(context);
      _toast(
        status == FirestoreWriteStatus.queued
            ? 'Saved offline — will sync when online.'
            : 'Food logged.',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('Could not save: $e');
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final est = widget.estimate;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Confirm Label'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Captured image preview
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              widget.imageFile,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 8),

          // Detected-calories banner
          _buildDetectedBanner(theme, est),
          const SizedBox(height: 20),

          // Editable fields
          const Text('Food name',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _nameController,
            decoration: _fieldDecoration(theme, 'e.g. Chocolate biscuits'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Calories',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _caloriesController,
                      keyboardType: TextInputType.number,
                      decoration: _fieldDecoration(theme, '0')
                          .copyWith(suffixText: 'kcal'),
                      onChanged: (_) => _calFromWeight = false,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Serving',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _servingController,
                      decoration: _fieldDecoration(theme, '1 serving'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Net weight → auto-calculates calories using per-100g rate when known.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Net weight eaten',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 6),
                  if (est.caloriesPer100g != null)
                    Text(
                      '(auto-calculates calories)',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _weightController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _fieldDecoration(theme, 'e.g. 145')
                    .copyWith(suffixText: 'g'),
              ),
              if (est.caloriesPer100g != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Label rate: ${est.caloriesPer100g!.round()} kcal per 100 g',
                  style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Date / time
          InkWell(
            onTap: _pickDateTime,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule, color: _kOrange, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    DateFormat('MMM d, yyyy • h:mm a').format(_timestamp),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  const Icon(Icons.edit, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Raw OCR text (collapsible)
          if (est.rawText.isNotEmpty) _buildRawTextSection(theme, est),

          const SizedBox(height: 24),

          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Log This Food',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectedBanner(ThemeData theme, NutritionLabelEstimate est) {
    final hasCalories = est.calories != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasCalories
            ? _kOrange.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            hasCalories ? Icons.check_circle : Icons.help_outline,
            color: hasCalories ? _kOrange : Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasCalories
                      ? 'Detected ${est.calories!.round()} kcal'
                      : 'No calorie value detected',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  hasCalories
                      ? est.calorieBasis.label
                      : 'Enter the value manually below',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (est.caloriesPer100g != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Also detected: ${est.caloriesPer100g!.round()} kcal per 100 g',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawTextSection(ThemeData theme, NutritionLabelEstimate est) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          title: const Text(
            'Raw scanned text',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          onExpansionChanged: (v) => setState(() => _showRawText = v),
          trailing: Icon(
            _showRawText ? Icons.expand_less : Icons.expand_more,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                est.rawText,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(ThemeData theme, String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHigh,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
