import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:calscan/logic/crud_records.dart';
import 'package:calscan/logic/nutrition_label_parser.dart';
import 'package:calscan/logic/offline_write.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

const _kOrange = Color(0xFFFF7E00);

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

  @override
  void dispose() {
    _controller?.dispose();
    unawaited(_recognizer.close());
    super.dispose();
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
      // mlkit read text here, user confirm after this
      final recognized = await _recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      final estimate = parseNutritionLabel(recognized.text);

      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => _NutritionLabelResultPage(
            imageFile: File(image.path),
            estimate: estimate,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not read label: $e')));
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
        body: Center(child: CircularProgressIndicator(color: _kOrange)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildPreview(_controller!)),
          _buildDimmedFrame(),
          _buildTopBar(),
          _buildCaptureDock(),
        ],
      ),
    );
  }

  Widget _buildPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);

    final screen = MediaQuery.sizeOf(context);
    var scale = screen.aspectRatio * previewSize.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return Transform.scale(
      scale: scale,
      child: Center(child: CameraPreview(controller)),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Back',
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.42),
              ),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Scan Nutrition Label',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDimmedFrame() {
    return IgnorePointer(
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 302,
              height: 390,
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.88),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Stack(
                children: const [
                  _Corner(alignment: Alignment.topLeft),
                  _Corner(alignment: Alignment.topRight),
                  _Corner(alignment: Alignment.bottomLeft),
                  _Corner(alignment: Alignment.bottomRight),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureDock() {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 18,
      right: 18,
      bottom: 24 + bottom,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isProcessing
                  ? 'Reading label...'
                  : 'Fit the nutrition panel inside the frame',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You can edit the name, calories, and serving before saving.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 76,
              height: 76,
              child: IconButton.filled(
                tooltip: 'Capture label',
                onPressed: _isProcessing ? null : _handleCapture,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white70,
                ),
                icon: _isProcessing
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          color: _kOrange,
                          strokeWidth: 3,
                        ),
                      )
                    : const Icon(
                        Icons.document_scanner_rounded,
                        color: _kOrange,
                        size: 34,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: _kOrange,
                size: 60,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _initialize,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final Alignment alignment;

  const _Corner({required this.alignment});

  @override
  Widget build(BuildContext context) {
    final isLeft = alignment.x < 0;
    final isTop = alignment.y < 0;
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.all(14),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border(
            left: isLeft
                ? const BorderSide(color: Colors.white, width: 4)
                : BorderSide.none,
            right: !isLeft
                ? const BorderSide(color: Colors.white, width: 4)
                : BorderSide.none,
            top: isTop
                ? const BorderSide(color: Colors.white, width: 4)
                : BorderSide.none,
            bottom: !isTop
                ? const BorderSide(color: Colors.white, width: 4)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

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
  final _formKey = GlobalKey<FormState>();
  final RecordService _records = RecordService();

  late final TextEditingController _nameController;
  late final TextEditingController _caloriesPerServingController;
  late final TextEditingController _servingSizeController;
  late final TextEditingController _servingsPerPackageController;
  late final TextEditingController _customEatenController;
  late final TextEditingController _customTotalController;

  DateTime _timestamp = DateTime.now();
  bool _saving = false;
  double _portionFraction = 1.0;
  bool _customPortion = false;

  @override
  void initState() {
    super.initState();
    final estimate = widget.estimate;
    _nameController = TextEditingController(text: estimate.productName);
    _caloriesPerServingController = TextEditingController(
      text: estimate.calories == null
          ? ''
          : estimate.calories!.round().toString(),
    );
    _servingSizeController = TextEditingController(
      text: _formatNumber(estimate.servingSize),
    );
    _servingsPerPackageController = TextEditingController(
      text: _formatNumber(estimate.servingsPerPackage ?? 1),
    );
    _customEatenController = TextEditingController(text: '1');
    _customTotalController = TextEditingController(
      text: (estimate.servingsPerPackage ?? 0) > 1
          ? _formatNumber(estimate.servingsPerPackage)
          : '',
    );

    for (final controller in [
      _caloriesPerServingController,
      _servingSizeController,
      _servingsPerPackageController,
      _customEatenController,
      _customTotalController,
    ]) {
      controller.addListener(_recalculate);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesPerServingController.dispose();
    _servingSizeController.dispose();
    _servingsPerPackageController.dispose();
    _customEatenController.dispose();
    _customTotalController.dispose();
    super.dispose();
  }

  void _recalculate() {
    if (mounted) setState(() {});
  }

  double get _caloriesPerServing =>
      double.tryParse(_caloriesPerServingController.text.trim()) ?? 0;

  double get _servingSize =>
      double.tryParse(_servingSizeController.text.trim()) ?? 0;

  double get _servingsPerPackage =>
      double.tryParse(_servingsPerPackageController.text.trim()) ?? 0;

  double get _customEaten =>
      double.tryParse(_customEatenController.text.trim()) ?? 0;

  double get _customTotal =>
      double.tryParse(_customTotalController.text.trim()) ?? 0;

  double get _selectedFraction {
    if (!_customPortion) return _portionFraction;
    if (_customTotal <= 0) return 0;
    // user put 1 / 24 here, no need thinking 0.04
    return _customEaten / _customTotal;
  }

  double get _totalWeight => _servingSize * _servingsPerPackage;

  double get _totalCaloriesToLog =>
      _selectedFraction * _servingsPerPackage * _caloriesPerServing;

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
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _nameController.text.trim();
    final calories = _totalCaloriesToLog.roundToDouble();
    final weight = _totalWeight * _selectedFraction;
    final servingDesc = _servingSize > 0
        ? '${_formatNumber(weight)} g ($_portionLabel)'
        : _portionLabel;

    setState(() => _saving = true);

    final mealData = <String, dynamic>{
      // send to firebase as normal meal record
      'mealName': name,
      'calories': calories.round(),
      'protein': 0,
      'carbs': 0,
      'fat': 0,
      'items': [
        {
          'key': null,
          'name': name,
          'calories': calories.roundToDouble(),
          'serving': servingDesc,
          'isCustom': true,
          'type': 'packaged_food',
        },
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
            ? 'Saved offline. Syncs later.'
            : 'Food logged.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save: $e');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Confirm Label'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            24 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            _buildImagePreview(),
            const SizedBox(height: 14),
            _buildLivePreview(theme),
            const SizedBox(height: 16),
            _buildScannedFields(theme),
            const SizedBox(height: 14),
            _buildPortionOptions(theme),
            const SizedBox(height: 14),
            _buildDateTile(theme),
            const SizedBox(height: 22),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _kOrange.withValues(alpha: 0.45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Log This Food',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.file(
        widget.imageFile,
        height: 190,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildLivePreview(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Food Name',
              hintText: 'e.g. Instant noodle cup',
              prefixIcon: Icon(Icons.fastfood_outlined),
            ),
            validator: (value) {
              if ((value ?? '').trim().isEmpty) return 'Enter food name';
              return null;
            },
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kOrange, Color(0xFFFF4B2B)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Text(
                  'Total Calories to Log',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_totalCaloriesToLog.round()} kcal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Based on $_portionLabel of ${_formatNumber(_totalWeight)} g total pack weight',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannedFields(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OCR scanned fields',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _numberField(
            controller: _caloriesPerServingController,
            label: 'Calories per Serving',
            suffix: 'kcal',
            icon: Icons.local_fire_department_outlined,
            allowZero: true,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _numberField(
                  controller: _servingSizeController,
                  label: 'Serving Size',
                  suffix: 'g',
                  icon: Icons.scale_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _numberField(
                  controller: _servingsPerPackageController,
                  label: 'Servings per Package',
                  suffix: 'x',
                  icon: Icons.inventory_2_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Total weight = serving size x servings per package',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortionOptions(ThemeData theme) {
    final oneServingFraction = _servingsPerPackage > 0
        ? 1 / _servingsPerPackage
        : 1.0;
    final options = [
      (label: 'Whole', caption: '100%', fraction: 1.0),
      (label: 'Half', caption: '50%', fraction: 0.5),
      if (_servingsPerPackage > 1)
        (label: '1 Serving', caption: '1 serve', fraction: oneServingFraction),
      (label: '1/4', caption: '25%', fraction: 0.25),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Eaten portion',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in options)
                _portionCard(
                  theme: theme,
                  label: option.label,
                  caption: option.caption,
                  fraction: option.fraction,
                  selected:
                      !_customPortion &&
                      _sameFraction(_portionFraction, option.fraction),
                ),
              _portionCard(
                theme: theme,
                label: 'Custom',
                caption: 'pieces',
                fraction: _selectedFraction,
                selected: _customPortion,
                custom: true,
              ),
            ],
          ),
          if (_customPortion) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _numberField(
                    controller: _customEatenController,
                    label: 'I ate',
                    suffix: 'pcs',
                    icon: Icons.check_circle_outline_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _numberField(
                    controller: _customTotalController,
                    label: 'Package has',
                    suffix: 'pcs',
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Example: candy bag, eat 1 piece from 24 pieces = put 1 and 24.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _portionCard({
    required ThemeData theme,
    required String label,
    required String caption,
    required double fraction,
    required bool selected,
    bool custom = false,
  }) {
    return SizedBox(
      width: 94,
      height: 76,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() {
            _customPortion = custom;
            if (!custom) _portionFraction = fraction;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? _kOrange : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? _kOrange : theme.dividerColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                style: TextStyle(
                  color: selected
                      ? Colors.white70
                      : theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required IconData icon,
    String? helperText,
    bool allowZero = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: helperText,
        prefixIcon: Icon(icon),
      ),
      validator: (value) {
        final number = double.tryParse((value ?? '').trim());
        if (number == null) return 'Enter number';
        if (number < 0 || (!allowZero && number == 0)) return 'Enter number';
        return null;
      },
    );
  }

  Widget _buildDateTile(ThemeData theme) {
    return InkWell(
      onTap: _pickDateTime,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule, color: _kOrange, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                DateFormat('MMM d, yyyy - h:mm a').format(_timestamp),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.edit, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  String get _portionLabel {
    if (_customPortion) {
      return '${_formatNumber(_customEaten)} of ${_formatNumber(_customTotal)} pieces';
    }
    if (_portionFraction == 1.0) return 'whole package';
    if (_portionFraction == 0.5) return 'half package';
    if (_portionFraction == 0.25) return '1/4 package';
    if (_sameFraction(_portionFraction, 1 / _servingsPerPackage)) {
      return '1 serving';
    }
    return '${_formatNumber(_portionFraction)}x package';
  }

  bool _sameFraction(double a, double b) => (a - b).abs() < 0.0001;

  String _formatNumber(double? value) {
    if (value == null || value <= 0) return '';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
}
