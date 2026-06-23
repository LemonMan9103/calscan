import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:calscan/home/manual_record.dart';
import 'package:calscan/logic/detection_utils.dart';
import 'package:calscan/logic/firestore_service.dart';
import 'package:calscan/logic/food_detection.dart';
import 'package:calscan/logic/food_lookup_service.dart';
import 'package:calscan/logic/offline_write.dart';
import 'package:calscan/logic/portion_estimation_service.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

const _kOrange = Color(0xFFFF7E00);

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
  final PortionEstimationService _portionService = PortionEstimationService();

  final Map<String, int> _portionIndices = {};
  final Map<String, int> _counts = {};
  final Set<String> _manualPortionKeys = {};
  bool _isSaving = false;
  bool _saved = false;
  bool _portionLoading = false;
  PortionEstimate? _portionEstimate;
  String? _portionMessage;
  late final List<FoodDetection> _detections;
  late final AnimationController _animationController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;
  Size? _sourceImageSize;

  @override
  void initState() {
    super.initState();
    _detections = _applyDishStrategy(widget.detections);
    for (final detection in _detections) {
      final arch = _lookup.getArchetype(detection.labelKey);
      if (arch.isCounter) {
        _counts[detection.labelKey] = arch.defaultCount;
      } else {
        _portionIndices[detection.labelKey] = _lookup.getDefaultPortionIndex(
          detection.labelKey,
        );
      }
    }
    _loadImageSize();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fadeIn = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _animationController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_estimatePortions());
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    unawaited(_portionService.close());
    super.dispose();
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
    // if whole dish exist, dont double count its small parts
    return selectDisplayDetections(
      detections,
      (labelKey) => _lookup.getCategory(labelKey) == 'whole_dish',
    );
  }

  Future<void> _estimatePortions() async {
    if (!_detections.any((detection) => _shouldUsePortionModel(detection))) {
      return;
    }

    setState(() {
      _portionLoading = true;
      _portionMessage = null;
    });

    try {
      await _portionService.loadModel();
      final estimate = await _portionService.estimate(widget.imageFile);
      if (!mounted) return;

      if (estimate == null || !estimate.hasUsableRatio) {
        setState(() {
          _portionLoading = false;
          _portionMessage = 'Portion helper needs plate or tapau box.';
        });
        return;
      }

      _applyPortionEstimate(estimate);
      setState(() {
        _portionEstimate = estimate;
        _portionLoading = false;
        _portionMessage = 'Portion suggested. You can still adjust it.';
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Portion estimate failed: $e');
      setState(() {
        _portionLoading = false;
        _portionMessage = 'Portion helper skipped. Pick manually.';
      });
    }
  }

  bool _shouldUsePortionModel(FoodDetection detection) {
    final arch = _lookup.getArchetype(detection.labelKey);
    if (arch.isCounter) return false;

    final entry = _lookup.lookup(detection.labelKey);
    final category = entry?.category.toLowerCase() ?? '';
    final archetype = arch.archetypeId.toLowerCase();
    final key = detection.labelKey.toLowerCase();

    return category == 'whole_dish' ||
        archetype.contains('rice') ||
        archetype.contains('plate') ||
        archetype.contains('bowl') ||
        key.contains('nasi') ||
        key.contains('rice');
  }

  void _applyPortionEstimate(PortionEstimate estimate) {
    // plate/tapau mask is ur reference for portion size only
    for (final detection in _detections) {
      final labelKey = detection.labelKey;
      if (_manualPortionKeys.contains(labelKey)) continue;
      if (!_shouldUsePortionModel(detection)) continue;

      final arch = _lookup.getArchetype(labelKey);
      final ratio = _ratioForDetection(detection, estimate);
      final suggestion = PortionRules.classify(ratio);
      final optionIndex = PortionRules.optionIndexForSuggestion(
        suggestion: suggestion,
        optionLabels: arch.options.map((option) => option.label).toList(),
        fallbackIndex: _portionIndices[labelKey] ?? arch.defaultIndex,
      );
      _portionIndices[labelKey] = optionIndex;
    }
  }

  double _ratioForDetection(FoodDetection detection, PortionEstimate estimate) {
    final key = detection.labelKey.toLowerCase();
    final display = _lookup.getDisplayName(detection.labelKey).toLowerCase();
    final arch = _lookup.getArchetype(detection.labelKey).archetypeId;
    final text = '$key $display $arch';

    if (text.contains('rice') || text.contains('nasi')) {
      return estimate.componentRatios['rice'] ?? estimate.totalFoodRatio;
    }
    if (text.contains('egg') || text.contains('telur')) {
      return estimate.componentRatios['fried_egg'] ?? estimate.totalFoodRatio;
    }
    if (text.contains('kangkung') ||
        text.contains('sayur') ||
        text.contains('vegetable') ||
        arch == 'bowl_side') {
      return estimate.componentRatios['fried_vegetables'] ??
          estimate.totalFoodRatio;
    }
    if (text.contains('ayam') ||
        text.contains('chicken') ||
        text.contains('curry')) {
      return estimate.componentRatios['curry_chicken'] ??
          estimate.totalFoodRatio;
    }
    return estimate.totalFoodRatio;
  }

  double get _totalCalories => _detections.fold(0.0, (total, detection) {
    final arch = _lookup.getArchetype(detection.labelKey);
    if (arch.isCounter) {
      return total +
          _lookup.getCaloriesForCount(
            detection.labelKey,
            _counts[detection.labelKey] ?? arch.defaultCount,
          );
    }
    return total +
        _lookup.getCaloriesForOption(
          detection.labelKey,
          _portionIndices[detection.labelKey] ?? arch.defaultIndex,
        );
  });

  double get _averageConfidence => _detections.isEmpty
      ? 0
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
    return _detections
        .map((detection) {
          final arch = _lookup.getArchetype(detection.labelKey);
          if (arch.isCounter) {
            return arch.countLabel(
              _counts[detection.labelKey] ?? arch.defaultCount,
            );
          }
          return arch
              .option(_portionIndices[detection.labelKey] ?? arch.defaultIndex)
              .label;
        })
        .join(' + ');
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
                detection.labelKey,
                _counts[detection.labelKey] ?? arch.defaultCount,
              )
            : _lookup.getMacrosForOption(
                detection.labelKey,
                _portionIndices[detection.labelKey] ?? arch.defaultIndex,
              );
        totalProtein += macros.protein;
        totalCarbs += macros.carbs;
        totalFat += macros.fat;
      }

      // send scan result to firebase
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
          const SnackBar(content: Text('Saved offline. Syncs later.')),
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          _buildAnnotatedPreview(),
          _buildTopBackButton(),
          Align(
            alignment: Alignment.bottomCenter,
            child: FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideUp,
                child: _detections.isEmpty
                    ? _buildNotDetectedPanel(theme)
                    : _buildDetectedPanel(theme),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBackButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: IconButton.filledTonal(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.48),
          ),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildAnnotatedPreview() {
    final previewHeight = MediaQuery.sizeOf(context).height * 0.48;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: previewHeight,
      child: ColoredBox(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final source = _sourceImageSize;
            if (source == null) {
              return Image.file(widget.imageFile, fit: BoxFit.cover);
            }

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
                Image.file(widget.imageFile, fit: BoxFit.contain),
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
      ),
    );
  }

  Widget _buildBoundingBox({
    required FoodDetection detection,
    required double scale,
    required double offsetX,
    required double offsetY,
  }) {
    final color = _confidenceColor(detection.confidence);
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
            borderRadius: BorderRadius.circular(12),
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
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetectedPanel(ThemeData theme) {
    return _ResultPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusPill(
                icon: Icons.auto_awesome,
                text: _detections.length == 1
                    ? '1 food detected'
                    : '${_detections.length} foods detected',
              ),
              const Spacer(),
              Text(
                _confidenceLabel(_averageConfidence),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: _kOrange,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Confirm your meal',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Adjust the portion before saving. You can retake or log manually if the model guessed wrong.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_portionLoading || _portionMessage != null) ...[
            const SizedBox(height: 10),
            _buildPortionHelperPill(theme),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _detections.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _buildDetectionCard(theme, _detections[index]),
            ),
          ),
          const SizedBox(height: 12),
          _buildTotalCard(theme),
          const SizedBox(height: 14),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildDetectionCard(ThemeData theme, FoodDetection detection) {
    final arch = _lookup.getArchetype(detection.labelKey);
    final calories = _caloriesFor(detection);
    final macros = _macrosFor(detection);
    final hasMacros = macros.protein + macros.carbs + macros.fat > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _kOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.restaurant, color: _kOrange, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lookup.getDisplayName(detection.labelKey),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_confidenceLabel(detection.confidence)} confidence',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${calories.round()} kcal',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: _kOrange,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (hasMacros)
                    Text(
                      'P ${macros.protein.toInt()}g C ${macros.carbs.toInt()}g F ${macros.fat.toInt()}g',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (arch.isCounter)
            _buildCounterRow(detection.labelKey, arch, theme)
          else
            _buildChipsRow(detection.labelKey, arch, theme),
        ],
      ),
    );
  }

  Widget _buildCounterRow(
    String labelKey,
    ArchetypeInfo arch,
    ThemeData theme,
  ) {
    final count = _counts[labelKey] ?? arch.defaultCount;
    return Row(
      children: [
        Expanded(
          child: Text(
            arch.archetypeLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _stepperButton(
          icon: Icons.remove,
          label: 'Decrease',
          onTap: count > arch.minCount
              ? () => setState(() => _counts[labelKey] = count - 1)
              : null,
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 86),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            arch.countLabel(count),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _stepperButton(
          icon: Icons.add,
          label: 'Increase',
          onTap: () => setState(() => _counts[labelKey] = count + 1),
        ),
      ],
    );
  }

  Widget _buildChipsRow(String labelKey, ArchetypeInfo arch, ThemeData theme) {
    final selectedIdx = _portionIndices[labelKey] ?? arch.defaultIndex;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(arch.options.length, (index) {
        final selected = index == selectedIdx;
        return ChoiceChip(
          label: Text(arch.options[index].label),
          selected: selected,
          onSelected: (_) => setState(() {
            _manualPortionKeys.add(labelKey);
            _portionIndices[labelKey] = index;
          }),
          showCheckmark: false,
          selectedColor: _kOrange,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          labelStyle: TextStyle(
            color: selected ? Colors.white : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
          side: BorderSide(color: selected ? _kOrange : theme.dividerColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        );
      }),
    );
  }

  Widget _buildTotalCard(ThemeData theme) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Container(
        key: ValueKey(_totalCalories.round()),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kOrange, Color(0xFFFF4B2B)]),
          borderRadius: BorderRadius.circular(18),
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
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${_totalCalories.round()} kcal',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
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
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context)
                ..pop()
                ..pop(),
              icon: const Icon(Icons.check_circle, color: Colors.white),
              label: const Text('Logged'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF28A745),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
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
              foregroundColor: _kOrange,
              side: const BorderSide(color: _kOrange),
              padding: const EdgeInsets.symmetric(vertical: 15),
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
            label: Text(_isSaving ? 'Saving...' : 'Save Meal'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _kOrange.withValues(alpha: 0.45),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotDetectedPanel(ThemeData theme) {
    return _ResultPanel(
      compact: true,
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              Icons.no_food_outlined,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No food detected',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try brighter lighting, move closer, or log the meal manually.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => showManualRecordDialog(context),
              icon: const Icon(Icons.edit_note),
              label: const Text('Log Manually'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              label: const Text('Retake Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _kOrange.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _kOrange, size: 15),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: _kOrange,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortionHelperPill(ThemeData theme) {
    final estimate = _portionEstimate;
    final message = _portionLoading
        ? 'Estimating plate portion...'
        : _portionMessage ?? 'Portion helper ready.';
    final reference = estimate == null
        ? null
        : '${estimate.referenceLabel.replaceAll('_', ' ')} ${(_safeRatio(estimate.totalFoodRatio) * 100).round()}%';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          _portionLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.donut_large, color: _kOrange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reference == null ? message : '$message ($reference)',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _safeRatio(double value) {
    if (value.isNaN || value.isInfinite) return 0;
    return value.clamp(0.0, 1.0).toDouble();
  }

  Widget _stepperButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton.filledTonal(
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: onTap == null
              ? Colors.grey.withValues(alpha: 0.10)
              : _kOrange.withValues(alpha: 0.14),
          foregroundColor: onTap == null ? Colors.grey : _kOrange,
        ),
      ),
    );
  }

  double _caloriesFor(FoodDetection detection) {
    // used for calculating calories after user pick portion
    final arch = _lookup.getArchetype(detection.labelKey);
    if (arch.isCounter) {
      return _lookup.getCaloriesForCount(
        detection.labelKey,
        _counts[detection.labelKey] ?? arch.defaultCount,
      );
    }
    return _lookup.getCaloriesForOption(
      detection.labelKey,
      _portionIndices[detection.labelKey] ?? arch.defaultIndex,
    );
  }

  ({double protein, double carbs, double fat}) _macrosFor(
    FoodDetection detection,
  ) {
    final arch = _lookup.getArchetype(detection.labelKey);
    if (arch.isCounter) {
      return _lookup.getMacrosForCount(
        detection.labelKey,
        _counts[detection.labelKey] ?? arch.defaultCount,
      );
    }
    return _lookup.getMacrosForOption(
      detection.labelKey,
      _portionIndices[detection.labelKey] ?? arch.defaultIndex,
    );
  }

  Color _confidenceColor(double confidence) {
    if (confidence >= 0.7) return const Color(0xFF28A745);
    if (confidence >= 0.45) return _kOrange;
    return const Color(0xFFDC3545);
  }

  String _confidenceLabel(double confidence) {
    if (confidence >= 0.7) return 'High';
    if (confidence >= 0.45) return 'Medium';
    return 'Low';
  }
}

class _ResultPanel extends StatelessWidget {
  final Widget child;
  final bool compact;

  const _ResultPanel({required this.child, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      height: MediaQuery.sizeOf(context).height * (compact ? 0.50 : 0.64),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 20, 20, 18 + bottom),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: child,
    );
  }
}
