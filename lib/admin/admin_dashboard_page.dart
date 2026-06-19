import 'package:flutter/material.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeaderCard(theme: theme),
          const SizedBox(height: 16),
          _AdminToolCard(
            icon: Icons.restaurant_menu_rounded,
            title: 'Nutrition Library',
            subtitle: 'Add, edit, or remove food nutrition data.',
            status: 'Next',
            onTap: () => _showSoon(context, 'Nutrition Library'),
          ),
          const SizedBox(height: 12),
          _AdminToolCard(
            icon: Icons.model_training_rounded,
            title: 'Food Model',
            subtitle: 'Manage model version and update detector files.',
            status: 'Planned',
            onTap: () => _showSoon(context, 'Food Model'),
          ),
          const SizedBox(height: 12),
          _AdminToolCard(
            icon: Icons.document_scanner_rounded,
            title: 'OCR Parser Rules',
            subtitle: 'Tune packaged-food label parsing behavior.',
            status: 'Planned',
            onTap: () => _showSoon(context, 'OCR Parser Rules'),
          ),
          const SizedBox(height: 12),
          _AdminToolCard(
            icon: Icons.verified_user_rounded,
            title: 'Admin Safety',
            subtitle: 'Version checks, rollback notes, and publish confirm.',
            status: 'Planned',
            onTap: () => _showSoon(context, 'Admin Safety'),
          ),
        ],
      ),
    );
  }

  void _showSoon(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title admin tool is coming next.')),
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
          colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.admin_panel_settings, color: Colors.white, size: 34),
          const SizedBox(height: 14),
          const Text(
            'Esti Admin',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Used for managing food data and app intelligence.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final VoidCallback onTap;

  const _AdminToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
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
              const SizedBox(width: 10),
              Chip(
                label: Text(status),
                visualDensity: VisualDensity.compact,
                side: BorderSide.none,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
