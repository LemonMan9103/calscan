import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const _kOrange = Color(0xFFFF7E00);

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  late DateTime _weekStart;
  late Future<_GoalProfile> _profileFuture;

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
    _profileFuture = _loadGoalProfile();
  }

  Future<_GoalProfile> _loadGoalProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const _GoalProfile();

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data() ?? {};
    final targetDate = data['targetDate'];

    return _GoalProfile(
      goal: data['goal']?.toString() ?? 'Maintain Weight',
      calorieTarget: (data['calorieTarget'] as num?)?.toInt() ?? 2000,
      targetDate: targetDate is Timestamp ? targetDate.toDate() : null,
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _weekMealsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    final end = _weekStart.add(const Duration(days: 7));
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('meals')
        .where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_weekStart),
        )
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .orderBy('timestamp')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text(
          'Progress',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: FutureBuilder<_GoalProfile>(
        future: _profileFuture,
        builder: (context, profileSnapshot) {
          final profile = profileSnapshot.data ?? const _GoalProfile();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _weekMealsStream(),
            builder: (context, mealSnapshot) {
              if (mealSnapshot.connectionState == ConnectionState.waiting &&
                  !mealSnapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: _kOrange),
                );
              }

              final days = _buildWeekDays(
                profile,
                mealSnapshot.data?.docs ?? [],
              );
              final achieved = days.where((day) => day.achieved).length;
              final weekEnd = _weekStart.add(const Duration(days: 6));

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _buildGoalCard(theme, profile),
                  const SizedBox(height: 14),
                  _buildWeekPicker(theme, weekEnd),
                  const SizedBox(height: 14),
                  _buildAchievementCard(theme, achieved, days.length),
                  const SizedBox(height: 14),
                  _buildWeeklyBars(theme, days, profile),
                  const SizedBox(height: 14),
                  _buildRuleCard(theme, profile),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildGoalCard(ThemeData theme, _GoalProfile profile) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: _goalColor(profile.goal).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              _goalIcon(profile.goal),
              color: _goalColor(profile.goal),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.goal,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${profile.calorieTarget} kcal daily target',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                _buildTargetDateChip(theme, profile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetDateChip(ThemeData theme, _GoalProfile profile) {
    final hasDate = profile.targetDate != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: hasDate
            ? _kOrange.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: hasDate
              ? _kOrange.withValues(alpha: 0.34)
              : theme.dividerColor,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasDate ? Icons.event_available_rounded : Icons.event_busy_outlined,
            size: 15,
            color: hasDate ? _kOrange : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              hasDate
                  ? 'Target ${DateFormat('MMM d, yyyy').format(profile.targetDate!)}'
                  : 'No target date',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: hasDate ? _kOrange : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekPicker(ThemeData theme, DateTime weekEnd) {
    final currentWeekStart = _startOfWeek(DateTime.now());
    final canGoNext = _weekStart.isBefore(currentWeekStart);
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: 'Previous week',
          onPressed: () {
            setState(
              () => _weekStart = _weekStart.subtract(const Duration(days: 7)),
            );
          },
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            '${DateFormat('MMM d').format(_weekStart)} - ${DateFormat('MMM d').format(weekEnd)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Next week',
          onPressed: canGoNext
              ? () {
                  setState(
                    () => _weekStart = _weekStart.add(const Duration(days: 7)),
                  );
                }
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _buildAchievementCard(ThemeData theme, int achieved, int totalDays) {
    final percent = totalDays == 0 ? 0.0 : achieved / totalDays;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_kOrange, Color(0xFFFF4B2B)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weekly Goal Achievement',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$achieved / $totalDays days achieved',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.24),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyBars(
    ThemeData theme,
    List<_DayProgress> days,
    _GoalProfile profile,
  ) {
    final maxCalories = [
      profile.calorieTarget.toDouble(),
      ...days.map((day) => day.calories),
    ].reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily intake this week',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _DayBar(day: day, maxCalories: maxCalories),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(ThemeData theme, _GoalProfile profile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: _kOrange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _ruleText(profile),
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_DayProgress> _buildWeekDays(
    _GoalProfile profile,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final totals = List<double>.filled(7, 0);

    for (final doc in docs) {
      final data = doc.data();
      final timestamp = data['timestamp'];
      if (timestamp is! Timestamp) continue;
      final dayIndex = timestamp.toDate().difference(_weekStart).inDays;
      if (dayIndex < 0 || dayIndex > 6) continue;
      totals[dayIndex] += (data['calories'] as num?)?.toDouble() ?? 0;
    }

    return List.generate(7, (index) {
      final date = _weekStart.add(Duration(days: index));
      final calories = totals[index];
      return _DayProgress(
        date: date,
        calories: calories,
        achieved: _isGoalAchieved(profile, calories),
      );
    });
  }

  bool _isGoalAchieved(_GoalProfile profile, double calories) {
    if (calories <= 0) return false;
    final goal = profile.goal.toLowerCase();
    final target = profile.calorieTarget.toDouble();

    // goal check used for weekly progress
    if (goal.contains('lose')) {
      final floor = target <= 1700 ? 1500.0 : target - 200;
      return calories < target && calories >= floor;
    }
    if (goal.contains('gain')) {
      return calories >= target;
    }
    if (goal.contains('custom')) {
      return (calories - target).abs() <= 100;
    }
    return (calories - target).abs() <= 100;
  }

  String _ruleText(_GoalProfile profile) {
    final goal = profile.goal.toLowerCase();
    if (goal.contains('lose')) {
      final floor = profile.calorieTarget <= 1700
          ? 1500
          : profile.calorieTarget - 200;
      return 'Lose weight counts when intake is below target but not below $floor kcal, because too low is not healthy.';
    }
    if (goal.contains('gain')) {
      return 'Gain weight counts when intake reaches at least ${profile.calorieTarget} kcal.';
    }
    return 'Maintain weight counts when intake is within +/-100 kcal of ${profile.calorieTarget} kcal.';
  }

  DateTime _startOfWeek(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    return local.subtract(Duration(days: local.weekday - DateTime.monday));
  }

  IconData _goalIcon(String goal) {
    final lower = goal.toLowerCase();
    if (lower.contains('lose')) return Icons.trending_down;
    if (lower.contains('gain')) return Icons.trending_up;
    return Icons.track_changes;
  }

  Color _goalColor(String goal) {
    final lower = goal.toLowerCase();
    if (lower.contains('lose')) return const Color(0xFF3B82F6);
    if (lower.contains('gain')) return const Color(0xFFA855F7);
    return const Color(0xFF22C55E);
  }
}

class _DayBar extends StatelessWidget {
  final _DayProgress day;
  final double maxCalories;

  const _DayBar({required this.day, required this.maxCalories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barHeight = maxCalories <= 0
        ? 0.0
        : (day.calories / maxCalories) * 118;
    final color = day.achieved ? const Color(0xFF22C55E) : _kOrange;

    return Column(
      children: [
        Text(
          day.calories <= 0 ? '-' : day.calories.round().toString(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: barHeight.clamp(8, 118),
            width: 22,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Icon(
          day.achieved ? Icons.check_circle : Icons.circle_outlined,
          size: 16,
          color: day.achieved
              ? const Color(0xFF22C55E)
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat('E').format(day.date).substring(0, 1),
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _GoalProfile {
  final String goal;
  final int calorieTarget;
  final DateTime? targetDate;

  const _GoalProfile({
    this.goal = 'Maintain Weight',
    this.calorieTarget = 2000,
    this.targetDate,
  });
}

class _DayProgress {
  final DateTime date;
  final double calories;
  final bool achieved;

  const _DayProgress({
    required this.date,
    required this.calories,
    required this.achieved,
  });
}
