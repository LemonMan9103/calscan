import 'dart:async';

import 'package:camera/camera.dart';
import 'package:calscan/logic/crud_records.dart';
import 'package:calscan/logic/nutrition_label_parser.dart';
import 'package:calscan/logic/offline_write.dart';
import 'package:calscan/logic/saved_food_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class NutritionLabelCameraPage extends StatefulWidget {
  const NutritionLabelCameraPage({super.key});

  @override
  State<NutritionLabelCameraPage> createState() =>
      _NutritionLabelCameraPageState();
}

class _NutritionLabelCameraPageState extends State<NutritionLabelCameraPage> {
  CameraController? _controller;
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool _isInitializing = true;
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera was found on this device.');
      }

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.max,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() => _isInitializing = false);
    } on CameraException catch (error) {
      _setError(error.description ?? 'The camera could not be initialized.');
    } catch (error) {
      _setError(error.toString().replaceFirst('Bad state: ', ''));
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
    unawaited(_textRecognizer.close());
    super.dispose();
  }

  Future<void> _captureLabel() async {
    final controller = _controller;
    if (_isProcessing ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final photo = await controller.takePicture();
      final recognized = await _textRecognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );
      final estimate = parseNutritionLabel(recognized.text);

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NutritionLabelResultPage(estimate: estimate),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to read this label: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _buildCameraPreview() {
    final controller = _controller!;
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);

    return Positioned.fill(
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nutrition Label')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_errorMessage!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (_isInitializing || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFF7E00))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraPreview(),
          CustomPaint(painter: const _LabelFramePainter()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: Row(
                  children: [
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const Spacer(),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Text(
                          'Nutrition Label',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(18),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Fill the frame with the nutrition panel. Keep the label flat and well-lit.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _isProcessing ? null : _captureLabel,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.document_scanner_outlined),
                      label: Text(
                        _isProcessing ? 'Reading label...' : 'Capture Label',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: const Color(0xFFFF7E00),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NutritionLabelResultPage extends StatefulWidget {
  final NutritionLabelEstimate estimate;

  const NutritionLabelResultPage({super.key, required this.estimate});

  @override
  State<NutritionLabelResultPage> createState() =>
      _NutritionLabelResultPageState();
}

class _NutritionLabelResultPageState extends State<NutritionLabelResultPage> {
  final _recordService = RecordService();
  final _savedFoodService = SavedFoodService();
  late final TextEditingController _nameController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _servingController;
  late final TextEditingController _quantityController;
  late CalorieBasis _calorieBasis;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.estimate.productName);
    _caloriesController = TextEditingController(
      text: widget.estimate.calories?.round().toString() ?? '',
    );
    _servingController = TextEditingController(text: widget.estimate.serving);
    _quantityController = TextEditingController(
      text: widget.estimate.calorieBasis == CalorieBasis.per100g ? '100' : '1',
    );
    _calorieBasis = widget.estimate.calorieBasis;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _servingController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  double get _baseCalories =>
      double.tryParse(_caloriesController.text.trim()) ?? 0;

  double get _quantity => double.tryParse(_quantityController.text.trim()) ?? 0;

  double get _totalCalories {
    if (_calorieBasis == CalorieBasis.per100g) {
      return _baseCalories * _quantity / 100;
    }
    return _baseCalories * _quantity;
  }

  String get _quantityLabel {
    switch (_calorieBasis) {
      case CalorieBasis.per100g:
        return 'Amount eaten';
      case CalorieBasis.perPackage:
        return 'Packages eaten';
      case CalorieBasis.perServing:
      case CalorieBasis.unknown:
        return 'Servings eaten';
    }
  }

  String? get _quantitySuffix =>
      _calorieBasis == CalorieBasis.per100g ? 'g' : null;

  void _selectSavedFood(SavedPackagedFood food) {
    setState(() {
      _nameController.text = food.name;
      _caloriesController.text = _formatNumber(food.calories);
      _servingController.text = food.serving;
      _calorieBasis = food.calorieBasis;
      _quantityController.text = food.calorieBasis == CalorieBasis.per100g
          ? '100'
          : '1';
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final serving = _servingController.text.trim();
    if (name.isEmpty || _baseCalories <= 0 || _quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirm the name, calories, and amount eaten.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final portion = _calorieBasis == CalorieBasis.per100g
          ? '${_formatNumber(_quantity)} g'
          : '${_formatNumber(_quantity)} ${_calorieBasis == CalorieBasis.perPackage ? 'package' : 'serving'}${_quantity == 1 ? '' : 's'}';
      final mealStatus = await _recordService.addMeal({
        'mealName': name,
        'calories': _totalCalories,
        'protein': 0.0,
        'carbs': 0.0,
        'fat': 0.0,
        'portion': portion,
        'source': 'nutrition_label',
        'items': [
          {
            'name': name,
            'serving': portion,
            'calories': _totalCalories,
            'calorieBasis': _calorieBasis.name,
            'baseCalories': _baseCalories,
          },
        ],
        'timestamp': Timestamp.now(),
      });
      final savedFoodStatus = await _savedFoodService.savePackagedFood(
        name: name,
        calories: _baseCalories,
        calorieBasis: _calorieBasis,
        serving: serving.isEmpty ? _calorieBasis.label : serving,
      );

      if (!mounted) return;
      final queued =
          mealStatus == FirestoreWriteStatus.queued ||
          savedFoodStatus == FirestoreWriteStatus.queued;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued
                ? 'Saved offline. Syncs when online.'
                : 'Packaged food added.',
          ),
        ),
      );
      Navigator.of(context)
        ..pop()
        ..pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save this record: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Review Label')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          // ── Hero: live total intake ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF4B2B).withValues(alpha: 0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.local_fire_department_rounded,
                        color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Estimated intake',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${_totalCalories.round()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text('kcal',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Saved foods quick-pick ───────────────────────────────────────
          StreamBuilder<List<SavedPackagedFood>>(
            stream: _savedFoodService.watchPackagedFoods(),
            builder: (context, snapshot) {
              final foods = snapshot.data ?? const <SavedPackagedFood>[];
              if (foods.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel(theme, 'Use a saved food'),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: foods.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final food = foods[index];
                        return ActionChip(
                          avatar: const Icon(Icons.history, size: 17),
                          label: Text(food.name),
                          onPressed: () => _selectSavedFood(food),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              );
            },
          ),

          // ── Name ─────────────────────────────────────────────────────────
          _sectionLabel(theme, 'Product'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Type the product name',
              prefixIcon: Icon(Icons.inventory_2_outlined),
            ),
          ),
          const SizedBox(height: 20),

          // ── Calorie basis as chips ───────────────────────────────────────
          _sectionLabel(theme, 'The label states calories…'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CalorieBasis.values.map((basis) {
              final selected = basis == _calorieBasis;
              return ChoiceChip(
                label: Text(basis.label),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _calorieBasis = basis;
                    _quantityController.text =
                        basis == CalorieBasis.per100g ? '100' : '1';
                  });
                },
                selectedColor: const Color(0xFFFF7E00),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                showCheckmark: false,
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // ── Calories + quantity ──────────────────────────────────────────
          _sectionLabel(theme, 'Numbers'),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _caloriesController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_numberFormatter],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Label calories',
                    suffixText: 'kcal',
                    prefixIcon: Icon(Icons.local_fire_department_outlined),
                    helperText: 'Edit if OCR misread it',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _quantityController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_numberFormatter],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: _quantityLabel,
                    suffixText: _quantitySuffix,
                    prefixIcon: const Icon(Icons.scale_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _servingController,
            decoration: const InputDecoration(
              labelText: 'Serving note (optional)',
              hintText: 'Example: 1 cup (75 g)',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 16),

          // ── Raw OCR text ─────────────────────────────────────────────────
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.text_snippet_outlined),
            title: const Text('Recognized label text'),
            subtitle: const Text('Open to check an OCR mistake'),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SelectableText(
                  widget.estimate.rawText.isEmpty
                      ? 'No readable text was found.'
                      : widget.estimate.rawText,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add_task),
            label: Text(_isSaving ? 'Saving...' : 'Add to Records'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: const Color(0xFFFF7E00),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
}

final _numberFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'^\d*\.?\d*'),
);

String _formatNumber(double value) {
  return value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}

class _LabelFramePainter extends CustomPainter {
  const _LabelFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.07,
        size.height * 0.18,
        size.width * 0.86,
        size.height * 0.48,
      ),
      const Radius.circular(20),
    );
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(frame)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlay, Paint()..color = Colors.black45);
    canvas.drawRRect(
      frame,
      Paint()
        ..color = const Color(0xFFFF7E00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
