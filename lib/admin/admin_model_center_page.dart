import 'dart:io';

import 'package:calscan/logic/food_detection.dart';
import 'package:calscan/logic/local_model_test_service.dart';
import 'package:calscan/logic/recognition_service.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

const _kOrange = Color(0xFFFF7E00);

enum _LocalModelKind { detection, portion }

class _LocalTestSlotData {
  File? modelFile;
  File? labelsFile;
  File? photoFile;
  String? modelName;
  String? labelsName;
  String? photoName;
  Object? result;
  String? error;
  bool loading = false;

  bool get hasAnyFile =>
      modelFile != null || labelsFile != null || photoFile != null;

  bool get ready =>
      modelFile != null && labelsFile != null && photoFile != null && !loading;

  void clearResult() {
    result = null;
    error = null;
  }

  void clearAll() {
    modelFile = null;
    labelsFile = null;
    photoFile = null;
    modelName = null;
    labelsName = null;
    photoName = null;
    loading = false;
    clearResult();
  }
}

class AdminModelCenterPage extends StatefulWidget {
  const AdminModelCenterPage({super.key});

  @override
  State<AdminModelCenterPage> createState() => _AdminModelCenterPageState();
}

class _AdminModelCenterPageState extends State<AdminModelCenterPage> {
  final LocalModelTestService _tester = LocalModelTestService();
  final ImagePicker _imagePicker = ImagePicker();
  final _LocalTestSlotData _detectionSlot = _LocalTestSlotData();
  final _LocalTestSlotData _portionSlot = _LocalTestSlotData();

  static const _portionLabels = [
    'curry_chicken',
    'fried_chicken',
    'fried_egg',
    'fried_vegetables',
    'plate',
    'rice',
    'tapau_box',
  ];

  Future<void> _pickModel(_LocalModelKind kind) async {
    final picked = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'TFLite model', extensions: ['tflite']),
      ],
    );
    if (picked == null) return;

    setState(() {
      final slot = _slotFor(kind);
      slot.modelFile = File(picked.path);
      slot.modelName = picked.name;
      slot.clearResult();
    });
  }

  Future<void> _pickLabels(_LocalModelKind kind) async {
    final picked = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Labels text file', extensions: ['txt']),
      ],
    );
    if (picked == null) return;

    setState(() {
      final slot = _slotFor(kind);
      slot.labelsFile = File(picked.path);
      slot.labelsName = picked.name;
      slot.clearResult();
    });
  }

  Future<void> _pickPhoto(_LocalModelKind kind) async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() {
      final slot = _slotFor(kind);
      slot.photoFile = File(picked.path);
      slot.photoName = picked.name;
      slot.clearResult();
    });
  }

  Future<void> _runLocalTest(_LocalModelKind kind) async {
    final slot = _slotFor(kind);
    if (slot.modelFile == null ||
        slot.labelsFile == null ||
        slot.photoFile == null) {
      _toast('Pick model, labels, and test photo first.');
      return;
    }

    setState(() {
      slot.loading = true;
      slot.clearResult();
    });

    try {
      final result = switch (kind) {
        _LocalModelKind.detection => await _tester.testDetection(
          modelFile: slot.modelFile!,
          labelsFile: slot.labelsFile!,
          imageFile: slot.photoFile!,
        ),
        _LocalModelKind.portion => await _tester.testPortion(
          modelFile: slot.modelFile!,
          labelsFile: slot.labelsFile!,
          imageFile: slot.photoFile!,
        ),
      };
      if (!mounted) return;
      setState(() {
        slot.loading = false;
        slot.result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        slot.loading = false;
        slot.error = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  void _clearSlot(_LocalModelKind kind) {
    setState(() => _slotFor(kind).clearAll());
  }

  _LocalTestSlotData _slotFor(_LocalModelKind kind) {
    return kind == _LocalModelKind.detection ? _detectionSlot : _portionSlot;
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
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: const Text('Model Center'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          28 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          _HeaderCard(theme: theme),
          const SizedBox(height: 16),
          _ModelStatusCard(
            icon: Icons.center_focus_strong_rounded,
            title: 'Food Recognition',
            subtitle: 'Main camera model that decides food label.',
            assetName: 'best_float32.tflite',
            status: 'Bundled in app',
            detail:
                '${RecognitionService.labels.length} labels. Label names must match food keys.',
            chips: const ['TFLite', 'YOLO detect', 'Food label'],
            slot: _detectionSlot,
            testSteps: const [
              'Load candidate detection model on admin phone',
              'Run sample meal photos locally',
              'Compare labels/confidence with bundled model',
              'Clear test files when done',
            ],
            onPickModel: () => _pickModel(_LocalModelKind.detection),
            onPickLabels: () => _pickLabels(_LocalModelKind.detection),
            onPickPhoto: () => _pickPhoto(_LocalModelKind.detection),
            onRunTest: () => _runLocalTest(_LocalModelKind.detection),
            onClear: () => _clearSlot(_LocalModelKind.detection),
          ),
          const SizedBox(height: 12),
          _ModelStatusCard(
            icon: Icons.donut_large_rounded,
            title: 'Portion Segmentation',
            subtitle: 'Runs only for rice/plate/tapau-style portion foods.',
            assetName: 'portion_model_float32.tflite',
            status: 'Bundled in app',
            detail:
                'Uses mask ratio: food area divided by plate/tapau usable area.',
            chips: _portionLabels,
            slot: _portionSlot,
            testSteps: const [
              'Load candidate portion model on admin phone',
              'Test rice, plate, and tapau examples',
              'Check suggested small/regular/large portions',
              'Clear test files when done',
            ],
            onPickModel: () => _pickModel(_LocalModelKind.portion),
            onPickLabels: () => _pickLabels(_LocalModelKind.portion),
            onPickPhoto: () => _pickPhoto(_LocalModelKind.portion),
            onRunTest: () => _runLocalTest(_LocalModelKind.portion),
            onClear: () => _clearSlot(_LocalModelKind.portion),
          ),
          const SizedBox(height: 16),
          _LocalTestingPlanCard(theme: theme),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final ThemeData theme;

  const _HeaderCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _kOrange.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.model_training_rounded, color: _kOrange),
          ),
          const SizedBox(height: 14),
          Text(
            'Local model testing',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Admins can test candidate models on their own phone only. Normal users keep using the stable bundled APK models.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelStatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String assetName;
  final String status;
  final String detail;
  final List<String> chips;
  final _LocalTestSlotData slot;
  final List<String> testSteps;
  final VoidCallback onPickModel;
  final VoidCallback onPickLabels;
  final VoidCallback onPickPhoto;
  final VoidCallback onRunTest;
  final VoidCallback onClear;

  const _ModelStatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.assetName,
    required this.status,
    required this.detail,
    required this.chips,
    required this.slot,
    required this.testSteps,
    required this.onPickModel,
    required this.onPickLabels,
    required this.onPickPhoto,
    required this.onRunTest,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _kOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: _kOrange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(label: status),
              ],
            ),
            const SizedBox(height: 14),
            _InfoRow(label: 'Current source', value: assetName),
            const SizedBox(height: 8),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips
                  .map(
                    (chip) => Chip(
                      label: Text(chip),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: theme.dividerColor),
                      backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            _ModelNotice(theme: theme),
            const SizedBox(height: 12),
            _LocalTestSlot(
              theme: theme,
              steps: testSteps,
              slot: slot,
              onPickModel: onPickModel,
              onPickLabels: onPickLabels,
              onPickPhoto: onPickPhoto,
              onRunTest: onRunTest,
              onClear: onClear,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelNotice extends StatelessWidget {
  final ThemeData theme;

  const _ModelNotice({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kOrange.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _kOrange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Local-only slot: test files affect this admin phone only. Normal users keep using the bundled APK model.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalTestSlot extends StatelessWidget {
  final ThemeData theme;
  final List<String> steps;
  final _LocalTestSlotData slot;
  final VoidCallback onPickModel;
  final VoidCallback onPickLabels;
  final VoidCallback onPickPhoto;
  final VoidCallback onRunTest;
  final VoidCallback onClear;

  const _LocalTestSlot({
    required this.theme,
    required this.steps,
    required this.slot,
    required this.onPickModel,
    required this.onPickLabels,
    required this.onPickPhoto,
    required this.onRunTest,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Testing slot',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          for (final step in steps) _StepLine(theme: theme, text: step),
          const SizedBox(height: 10),
          _PickedFileRow(
            icon: Icons.memory_rounded,
            label: 'Model',
            value: slot.modelName ?? 'Pick .tflite',
            onTap: onPickModel,
          ),
          const SizedBox(height: 8),
          _PickedFileRow(
            icon: Icons.format_list_bulleted_rounded,
            label: 'Labels',
            value: slot.labelsName ?? 'Pick labels .txt',
            onTap: onPickLabels,
          ),
          const SizedBox(height: 8),
          _PickedFileRow(
            icon: Icons.photo_rounded,
            label: 'Photo',
            value: slot.photoName ?? 'Pick test photo',
            onTap: onPickPhoto,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: slot.ready ? onRunTest : null,
                  icon: slot.loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(slot.loading ? 'Testing...' : 'Run Test'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Clear local test files',
                onPressed:
                    slot.hasAnyFile || slot.result != null || slot.error != null
                    ? onClear
                    : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          if (slot.error != null) ...[
            const SizedBox(height: 10),
            _LocalTestError(theme: theme, message: slot.error!),
          ],
          if (slot.result != null) ...[
            const SizedBox(height: 10),
            _LocalTestResultView(theme: theme, result: slot.result!),
          ],
        ],
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  final ThemeData theme;
  final String text;

  const _StepLine({required this.theme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: Color(0xFF059669),
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickedFileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _PickedFileRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Icon(icon, color: _kOrange, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalTestError extends StatelessWidget {
  final ThemeData theme;
  final String message;

  const _LocalTestError({required this.theme, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalTestResultView extends StatelessWidget {
  final ThemeData theme;
  final Object result;

  const _LocalTestResultView({required this.theme, required this.result});

  @override
  Widget build(BuildContext context) {
    if (result is LocalDetectionTestResult) {
      return _DetectionResultView(
        theme: theme,
        result: result as LocalDetectionTestResult,
      );
    }
    if (result is LocalPortionTestResult) {
      return _PortionResultView(
        theme: theme,
        result: result as LocalPortionTestResult,
      );
    }
    return const SizedBox.shrink();
  }
}

class _DetectionResultView extends StatelessWidget {
  final ThemeData theme;
  final LocalDetectionTestResult result;

  const _DetectionResultView({required this.theme, required this.result});

  @override
  Widget build(BuildContext context) {
    final detections = result.detections.take(6).toList();
    return _ResultShell(
      theme: theme,
      title: 'Detection test result',
      children: [
        _ResultMetaLine(
          theme: theme,
          text:
              'Input ${result.inputShape} / Output ${result.outputShape} / ${result.labels.length} labels',
        ),
        const SizedBox(height: 8),
        if (detections.isEmpty)
          _ResultMetaLine(theme: theme, text: 'No food detected in this photo.')
        else
          for (final detection in detections)
            _DetectionLine(theme: theme, detection: detection),
      ],
    );
  }
}

class _PortionResultView extends StatelessWidget {
  final ThemeData theme;
  final LocalPortionTestResult result;

  const _PortionResultView({required this.theme, required this.result});

  @override
  Widget build(BuildContext context) {
    final estimate = result.estimate;
    return _ResultShell(
      theme: theme,
      title: 'Portion test result',
      children: [
        _ResultMetaLine(
          theme: theme,
          text:
              'Input ${result.inputShape} / Detect ${result.detectionShape} / Mask ${result.prototypeShape}',
        ),
        const SizedBox(height: 8),
        _ResultMetaLine(theme: theme, text: '${result.labels.length} labels'),
        const SizedBox(height: 8),
        if (estimate == null || !estimate.hasUsableRatio)
          _ResultMetaLine(
            theme: theme,
            text: 'No usable plate/tapau reference found in this photo.',
          )
        else ...[
          _ResultMetaLine(
            theme: theme,
            text:
                'Reference ${estimate.referenceLabel.replaceAll('_', ' ')} / total ratio ${(estimate.totalFoodRatio * 100).round()}%',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in estimate.componentRatios.entries)
                Chip(
                  label: Text(
                    '${entry.key.replaceAll('_', ' ')} ${(entry.value * 100).round()}%',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ResultShell extends StatelessWidget {
  final ThemeData theme;
  final String title;
  final List<Widget> children;

  const _ResultShell({
    required this.theme,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF059669).withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF059669).withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF059669),
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _ResultMetaLine extends StatelessWidget {
  final ThemeData theme;
  final String text;

  const _ResultMetaLine({required this.theme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _DetectionLine extends StatelessWidget {
  final ThemeData theme;
  final FoodDetection detection;

  const _DetectionLine({required this.theme, required this.detection});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              detection.labelKey.replaceAll('_', ' '),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${(detection.confidence * 100).round()}%',
            style: theme.textTheme.labelLarge?.copyWith(
              color: _kOrange,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalTestingPlanCard extends StatelessWidget {
  final ThemeData theme;

  const _LocalTestingPlanCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Test locally', 'Candidate models run only on the admin device.'),
      (
        'Validate contract',
        'Labels, input shape, and output shape must match.',
      ),
      (
        'Compare results',
        'Use real sample photos before replacing app assets.',
      ),
      ('Release by APK', 'Accepted models ship in the next APK build.'),
    ];

    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Simple release flow',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'If a tested model is good, replace the bundled asset and release a new APK. No global Firebase model switch is used.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < steps.length; i++)
              _WorkflowStep(
                index: i + 1,
                title: steps[i].$1,
                body: steps[i].$2,
                isLast: i == steps.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  final int index;
  final String title;
  final String body;
  final bool isLast;

  const _WorkflowStep({
    required this.index,
    required this.title,
    required this.body,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: _kOrange,
              child: Text(
                '$index',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (!isLast)
              Container(width: 2, height: 34, color: theme.dividerColor),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;

  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _kOrange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _kOrange,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
