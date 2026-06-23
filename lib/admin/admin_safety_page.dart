import 'package:flutter/material.dart';

const _kOrange = Color(0xFFFF7E00);

class AdminSafetyPage extends StatelessWidget {
  const AdminSafetyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: const Text('Dev Tools'),
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
          const _SafetyItem(
            icon: Icons.verified_user_rounded,
            title: 'Admin role gate',
            status: 'Required',
            body:
                'Only users/{uid}.role = admin should write admin collections.',
          ),
          const SizedBox(height: 10),
          const _SafetyItem(
            icon: Icons.science_rounded,
            title: 'Model draft testing',
            status: 'Required',
            body:
                'New food or portion model should run sample scans before it becomes live.',
          ),
          const SizedBox(height: 10),
          const _SafetyItem(
            icon: Icons.history_rounded,
            title: 'Model rollback metadata',
            status: 'Later',
            body:
                'Keep previous model metadata so admin can go back if detection gets worse.',
          ),
          const SizedBox(height: 10),
          const _SafetyItem(
            icon: Icons.cloud_upload_rounded,
            title: 'Storage path rules',
            status: 'Required',
            body:
                'Food images and model files should live in separate Firebase Storage folders.',
          ),
          const SizedBox(height: 10),
          const _SafetyItem(
            icon: Icons.photo_camera_back_rounded,
            title: 'User training images',
            status: 'Later',
            body:
                'Only collect failed scan photos if user gives consent, then review before retraining.',
          ),
          const SizedBox(height: 16),
          _RulesSnippetCard(theme: theme),
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
        gradient: const LinearGradient(
          colors: [_kOrange, Color(0xFFFF4B2B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.developer_mode_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Developer tools',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Useful checks for model updates, Firebase rules, and training-data planning.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.84),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String status;
  final String body;

  const _SafetyItem({
    required this.icon,
    required this.title,
    required this.status,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: const Color(0xFF059669)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _StatusPill(label: status),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RulesSnippetCard extends StatelessWidget {
  final ThemeData theme;

  const _RulesSnippetCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    const snippet =
        "users/{uid}.role == 'admin'\n"
        'food_library: signed-in read, admin write\n'
        'food_images: signed-in read, admin write\n'
        'model_drafts: admin write\n'
        'training_images: user opt-in write, admin read';

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
              'Rules checklist',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Use this as the mental model when updating Firestore and Storage rules.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                snippet,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;

  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kOrange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _kOrange,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
