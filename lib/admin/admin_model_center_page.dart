import 'package:calscan/logic/recognition_service.dart';
import 'package:flutter/material.dart';

const _kOrange = Color(0xFFFF7E00);

class AdminModelCenterPage extends StatelessWidget {
  const AdminModelCenterPage({super.key});

  static const _portionLabels = [
    'curry_chicken',
    'fried_chicken',
    'fried_egg',
    'fried_vegetables',
    'plate',
    'rice',
    'tapau_box',
  ];

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
          ),
          const SizedBox(height: 16),
          _TrainingDataCard(theme: theme),
          const SizedBox(height: 16),
          _PublishWorkflowCard(theme: theme),
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
            'Model update workspace',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use this page to test draft food and portion models before they replace the live app.',
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

  const _ModelStatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.assetName,
    required this.status,
    required this.detail,
    required this.chips,
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
              'Final sprint mode: this build uses bundled models. Test model changes by replacing app assets, running checks, then releasing a new APK.',
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

class _PublishWorkflowCard extends StatelessWidget {
  final ThemeData theme;

  const _PublishWorkflowCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Upload draft', 'Save model file and labels as an unpublished version.'),
      ('Run sample tests', 'Admin checks real photos before users receive it.'),
      ('Collect feedback', 'Use failed user scans only if user allowed it.'),
      ('Review contract', 'Labels, input shape, and output shape must match.'),
      ('Publish safely', 'Only then replace the live model version.'),
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
              'Safe publish flow',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'This is the safe flow for a future dynamic model-update system.',
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

class _TrainingDataCard extends StatelessWidget {
  final ThemeData theme;

  const _TrainingDataCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF059669).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF059669).withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  color: Color(0xFF059669),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'User photos for model improvement',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Settings now has an opt-in toggle. The next part is saving failed scan photos only when the user allowed it.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PlanChip(label: 'Opt-in only'),
              _PlanChip(label: 'Admin review'),
              _PlanChip(label: 'Firebase Storage'),
              _PlanChip(label: 'Retraining dataset'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanChip extends StatelessWidget {
  final String label;

  const _PlanChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: const Color(0xFF059669).withValues(alpha: 0.12),
      side: BorderSide.none,
      labelStyle: const TextStyle(
        color: Color(0xFF047857),
        fontWeight: FontWeight.w800,
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
