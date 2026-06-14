import 'dart:math' as math;
import 'dart:io';

import 'package:calscan/logic/firestore_service.dart';
import 'package:calscan/logic/detection_utils.dart';
import 'package:calscan/logic/food_detection.dart';
import 'package:calscan/logic/food_lookup_service.dart';
import 'package:calscan/logic/offline_write.dart';
import 'package:calscan/home/manual_record.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ScanResultPage extends StatefulWidget {
  final File imageFile;
  final List<FoodDetection> detections;

  const ScanResultPage({
    super.key,
    required this.imageFile,
    required this.detections,
  });

  @override
  State<ScanResultPage> createState() => _ScanResultPageState();
}

class _ScanResultPageState extends State<ScanResultPage>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final FoodLookupService _lookup = FoodLookupService();

  final Map<String, int> _portionIndices = {};
  final Map<String, int> _counts = {};
  bool _isSaving = false;
  bool _saved = false;
  late final List<FoodDetection> _detections;
  late final AnimationController _animationController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;
  Size? _sourceImageSize;

  @override
  void initState() {
    super.initState();
    _detections = _applyDishStrategy(widget.detections);
    for (final d in _detections) {
      final arch = _lookup.getArchetype(d.labelKey);
      if (arch.isCounter) {
        _counts[d.labelKey] = arch.defaultCount;
      } else {
        _portionIndices[d.labelKey] = _lookup.getDefaultPortionIndex(d.labelKey);
      }
    }
    _loadImageSize();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeIn = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );
    _animationController.forward();
  }

  void _loadImageSize() {
    final decoded = img.decodeImage(widget.imageFile.readAsBytesSync());
    if (decoded == null) return;
    _sourceImageSize = Size(
      decoded.width.toDouble(),
      decoded.height.toDouble(),
    );
  }

  List<FoodDetection> _applyDishStrategy(List<FoodDetection> detections) {
    return selectDisplayDetections(
      detections,
      (labelKey) => _lookup.getCategory(labelKey) == 'whole_dish',
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  double get _totalCalories => _detections.fold(0.0, (total, d) {
    final arch = _lookup.getArchetype(d.labelKey);
    if (arch.isCounter) {
      return total + _lookup.getCaloriesForCount(
          d.labelKey, _counts[d.labelKey] ?? arch.defaultCount);
    }
    return total + _lookup.getCaloriesForOption(
        d.labelKey, _portionIndices[d.labelKey] ?? 0);
  });

  double get _averageConfidence => _detections.isEmpty
      ? 0.0
      : _detections.fold(
              0.0,
              (total, detection) => total + detection.confidence,
            ) /
            _detections.length;

  String get _mealName => _detections
      .map((detection) => _lookup.getDisplayName(detection.labelKey))
      .join(' + ');

  String get _servingLabel {
    if (_detections.isEmpty) return '1 serving';
    return _detections.map((d) {
      final arch = _lookup.getArchetype(d.labelKey);
      if (arch.isCounter) {
        final count = _counts[d.labelKey] ?? arch.defaultCount;
        return arch.countLabel(count);
      }
      final idx = _portionIndices[d.labelKey] ?? 0;
      return arch.option(idx).label;
    }).join(' + ');
  }

  Future<void> _saveAndLog() async {
    if (_isSaving || _saved || _detections.isEmpty) return;
    setState(() => _isSaving = true);

    try {
      double totalProtein = 0, totalCarbs = 0, totalFat = 0;
      for (final detection in _detections) {
        final arch = _lookup.getArchetype(detection.labelKey);
        final macros = arch.isCounter
            ? _lookup.getMacrosForCount(
                detection.labelKey, _counts[detection.labelKey] ?? arch.defaultCount)
            : _lookup.getMacrosForOption(
                detection.labelKey, _portionIndices[detection.labelKey] ?? 0);
        totalProtein += macros.protein;
        totalCarbs += macros.carbs;
        totalFat += macros.fat;
      }

      final status = await _firestoreService.saveMeal(
        mealName: _mealName,
        calories: _totalCalories,
        protein: totalProtein,
        carbs: totalCarbs,
        fat: totalFat,
        portion: _servingLabel,
      );

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saved = true;
      });
      if (status == FirestoreWriteStatus.queued) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved offline. Syncs when online.')),
        );
      }

    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to save this meal: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          _buildAnnotatedPreview(),
          Positioned(
            top: MediaQuery.sizeOf(context).height * 0.28,
            left: 0,
            right: 0,
            height: MediaQuery.sizeOf(context).height * 0.18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Theme.of(context).scaffoldBackgroundColor,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: _CircleIconButton(
                icon: Icons.arrow_back,
                onTap: () => Navigator.pop(context),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideUp,
                child: _detections.isEmpty
                    ? _buildNotDetectedCard()
                    : _buildDetectedCard(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnotatedPreview() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: MediaQuery.sizeOf(context).height * 0.46,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final source = _sourceImageSize;
          if (source == null) {
            return Image.file(widget.imageFile, fit: BoxFit.cover);
          }

          final fit = BoxFit.contain;
          final scale = math.min(
            constraints.maxWidth / source.width,
            constraints.maxHeight / source.height,
          );
          final displayWidth = source.width * scale;
          final displayHeight = source.height * scale;
          final offsetX = (constraints.maxWidth - displayWidth) / 2;
          final offsetY = (constraints.maxHeight - displayHeight) / 2;

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.file(widget.imageFile, fit: fit),
              for (final detection in _detections)
                _buildBoundingBox(
                  detection: detection,
                  scale: scale,
                  offsetX: offsetX,
                  offsetY: offsetY,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBoundingBox({
    required FoodDetection detection,
    required double scale,
    required double offsetX,
    required double offsetY,
  }) {
    final color = _colorForConfidence(detection.confidence);
    final left = detection.left * scale + offsetX;
    final top = detection.top * scale + offsetY;
    final width = (detection.right - detection.left) * scale;
    final height = (detection.bottom - detection.top) * scale;

    if (width <= 2 || height <= 2) return const SizedBox.shrink();

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(10),
            color: color.withValues(alpha: 0.08),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _lookup.getDisplayName(detection.labelKey),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _colorForConfidence(double confidence) {
    if (confidence >= 0.7) return const Color(0xFF28A745);
    if (confidence >= 0.45) return const Color(0xFFFF7E00);
    return const Color(0xFFDC3545);
  }

  Widget _buildDetectedCard() {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return Container(
      height: screenHeight * 0.64,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildChip(
                icon: Icons.auto_awesome,
                label: _detections.length == 1
                    ? '1 food detected'
                    : '${_detections.length} foods detected',
              ),
              const Spacer(),
              Text(
                '${(_averageConfidence * 100).round()}% avg. confidence',
                style: const TextStyle(
                  color: Color(0xFFFF7E00),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildLegendDot(const Color(0xFF28A745), 'High (≥70%)'),
              const SizedBox(width: 12),
              _buildLegendDot(const Color(0xFFFF7E00), 'Medium (45–69%)'),
              const SizedBox(width: 12),
              _buildLegendDot(const Color(0xFFDC3545), 'Low (<45%)'),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Detected Food',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _detections.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _buildDetectionRow(_detections[index]),
            ),
          ),
          const SizedBox(height: 12),
          _buildCalorieCard(),
          const SizedBox(height: 14),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildDetectionRow(FoodDetection detection) {
    final theme = Theme.of(context);
    final arch = _lookup.getArchetype(detection.labelKey);

    final double calories;
    final ({double protein, double carbs, double fat}) macros;
    if (arch.isCounter) {
      final count = _counts[detection.labelKey] ?? arch.defaultCount;
      calories = _lookup.getCaloriesForCount(detection.labelKey, count);
      macros = _lookup.getMacrosForCount(detection.labelKey, count);
    } else {
      final idx = _portionIndices[detection.labelKey] ?? arch.defaultIndex;
      calories = _lookup.getCaloriesForOption(detection.labelKey, idx);
      macros = _lookup.getMacrosForOption(detection.labelKey, idx);
    }
    final hasMacros = macros.protein + macros.carbs + macros.fat > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF7E00).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.restaurant, color: Color(0xFFFF7E00), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lookup.getDisplayName(detection.labelKey),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      '${(detection.confidence * 100).toStringAsFixed(1)}% confidence',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${calories.toInt()} kcal',
                    style: const TextStyle(
                        color: Color(0xFFFF4B2B), fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (hasMacros)
                    Text(
                      'P${macros.protein.toInt()} C${macros.carbs.toInt()} F${macros.fat.toInt()}',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 10),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (arch.isCounter)
            _buildCounterRow(detection.labelKey, arch, theme)
          else
            _buildChipsRow(detection.labelKey, arch, theme),
        ],
      ),
    );
  }

  Widget _buildCounterRow(String labelKey, ArchetypeInfo arch, ThemeData theme) {
    final count = _counts[labelKey] ?? arch.defaultCount;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: count > arch.minCount
              ? () => setState(() => _counts[labelKey] = count - 1)
              : null,
          icon: const Icon(Icons.remove_circle_outline),
          color: const Color(0xFFFF7E00),
          iconSize: 26,
        ),
        const SizedBox(width: 4),
        Text(
          arch.countLabel(count),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () => setState(() => _counts[labelKey] = count + 1),
          icon: const Icon(Icons.add_circle_outline),
          color: const Color(0xFFFF7E00),
          iconSize: 26,
        ),
      ],
    );
  }

  Widget _buildChipsRow(String labelKey, ArchetypeInfo arch, ThemeData theme) {
    final selectedIdx = _portionIndices[labelKey] ?? arch.defaultIndex;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(arch.options.length, (i) {
        final opt = arch.options[i];
        final sel = i == selectedIdx;
        return GestureDetector(
          onTap: () => setState(() => _portionIndices[labelKey] = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: sel ? const Color(0xFFFF7E00) : theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: sel ? const Color(0xFFFF7E00) : theme.dividerColor,
              ),
            ),
            child: Text(
              opt.label,
              style: TextStyle(
                color: sel ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCalorieCard() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(_totalCalories.toInt()),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.local_fire_department,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 12),
            const Text(
              'Estimated total',
              style: TextStyle(color: Colors.white70),
            ),
            const Spacer(),
            Text(
              '${_totalCalories.toInt()} kcal',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    if (_saved) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context)
                ..pop()
                ..pop(),
              icon: const Icon(Icons.home_outlined),
              label: const Text('Home'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context)
                  ..pop()
                  ..pop();
              },
              icon: const Icon(Icons.check_circle, color: Colors.white),
              label: const Text(
                'Logged!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF28A745),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.refresh),
            label: const Text('Retake'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF7E00),
              side: const BorderSide(color: Color(0xFFFF7E00)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAndLog,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add_circle_outline, color: Colors.white),
            label: Text(
              _isSaving ? 'Saving...' : 'Save & Log',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF7E00),
              disabledBackgroundColor: Colors.orange.shade300,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotDetectedCard() {
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.52,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 36),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Icon(Icons.no_food_outlined, size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 20),
          const Text(
            'No Food Detected',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'Make sure the food is clearly visible, well-lit, and inside the frame.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.5),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showManualRecordDialog(context),
              icon: const Icon(Icons.edit_note),
              label: const Text('Log Manually'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              label: const Text(
                'Retake Photo',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7E00),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
