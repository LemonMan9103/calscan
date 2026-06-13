import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Progress',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _ProgressBody(),
    );
  }
}

class _ProgressBody extends StatelessWidget {
  final _db = FirebaseFirestore.instance;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  _ProgressBody();

  /// Fetch last 7 days of meals from Firestore
  Stream<QuerySnapshot> _getLast7DaysMeals() {
    if (_uid == null) return const Stream.empty();
    final cutoff = DateTime.now().subtract(const Duration(days: 6));
    final startOfCutoff = DateTime(cutoff.year, cutoff.month, cutoff.day);
    return _db
        .collection('users')
        .doc(_uid)
        .collection('meals')
        .where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfCutoff),
        )
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getLast7DaysMeals(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF7E00)),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        // ── Aggregate data ────────────────────────────────────────────
        // Build a map of  dateLabel -> {mealCount, totalCalories}
        final now = DateTime.now();
        final Map<String, _DayStats> dayStatsMap = {};

        for (int i = 6; i >= 0; i--) {
          final d = now.subtract(Duration(days: i));
          final key = DateFormat('EEE').format(d); // Mon, Tue…
          dayStatsMap[key] = _DayStats();
        }

        // Today's meals for line chart
        final List<FlSpot> todaySpots = [];
        double cumulativeToday = 0;

        for (var doc in docs) {
          final ts = (doc['timestamp'] as Timestamp).toDate();
          final key = DateFormat('EEE').format(ts);
          final cals = (doc['calories'] as num).toDouble();

          if (dayStatsMap.containsKey(key)) {
            dayStatsMap[key]!.mealCount++;
            dayStatsMap[key]!.totalCalories += cals;
          }

          // Line chart: today only
          final isToday =
              ts.year == now.year && ts.month == now.month && ts.day == now.day;
          if (isToday) {
            cumulativeToday += cals;
            todaySpots.add(FlSpot(ts.hour + ts.minute / 60, cumulativeToday));
          }
        }

        // Streak: count consecutive days from today going backwards that have meals
        int streak = 0;
        for (int i = 0; i < 7; i++) {
          final d = now.subtract(Duration(days: i));
          final key = DateFormat('EEE').format(d);
          if ((dayStatsMap[key]?.mealCount ?? 0) > 0) {
            streak++;
          } else {
            break;
          }
        }

        // Avg meals per active day (days with at least 1 meal)
        final activeDays = dayStatsMap.values
            .where((s) => s.mealCount > 0)
            .length;
        final totalMeals7 = dayStatsMap.values.fold(
          0,
          (s, d) => s + d.mealCount,
        );
        final avgMeals = activeDays > 0 ? totalMeals7 / activeDays : 0.0;

        // Bar chart data (ordered Mon→Sun or last 7 days in order)
        final dayKeys = dayStatsMap.keys.toList();
        final barGroups = dayKeys.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: dayStatsMap[e.value]!.mealCount.toDouble(),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                width: 20,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
            ],
          );
        }).toList();

        final maxBarY = dayStatsMap.values
            .map((s) => s.mealCount.toDouble())
            .fold(0.0, (a, b) => a > b ? a : b);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Stat cards ──────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      context: context,
                      title: 'Streak',
                      value: '$streak',
                      unit: streak == 1 ? 'day' : 'days',
                      icon: Icons.local_fire_department_rounded,
                      color: const Color(0xFFFF7E00),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      context: context,
                      title: 'Avg / Day',
                      value: avgMeals.toStringAsFixed(1),
                      unit: 'meals',
                      icon: Icons.restaurant_rounded,
                      color: const Color(0xFF4D82F5),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      context: context,
                      title: 'This Week',
                      value: '$totalMeals7',
                      unit: 'meals',
                      icon: Icons.calendar_today_rounded,
                      color: const Color(0xFF30C060),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Meals per day bar chart ──────────────────────────────
              _buildSectionTitle('Meals per Day', 'Last 7 days'),
              const SizedBox(height: 12),
              _buildCard(
                context: context,
                height: 210,
                child: totalMeals7 == 0
                    ? Builder(
                        builder: (ctx) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.restaurant_outlined,
                                size: 40,
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.35),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No meals logged this week',
                                style: TextStyle(
                                  color: Theme.of(
                                    ctx,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: (maxBarY < 3 ? 5 : maxBarY + 2),
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                            BarTooltipItem(
                              '${rod.toY.toInt()} meals',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                      ),
                    ),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= dayKeys.length) {
                              return const SizedBox();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                dayKeys[idx],
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          interval: 1,
                          getTitlesWidget: (value, meta) => Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 1,
                      getDrawingHorizontalLine: (_) => FlLine(
                      color: Theme.of(context).dividerColor,
                      strokeWidth: 1,
                    ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: barGroups,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Today's calorie line chart ───────────────────────────
              _buildSectionTitle(
                "Today's Calories",
                'Cumulative intake by hour',
              ),
              const SizedBox(height: 12),
              _buildCard(
                context: context,
                height: 230,
                child: todaySpots.isEmpty
                    ? Builder(
                        builder: (ctx) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bar_chart_outlined,
                                size: 40,
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.35),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No meals logged today yet',
                                style: TextStyle(
                                  color: Theme.of(
                                    ctx,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : LineChart(
                        LineChartData(
                          minX: 0,
                          maxX: 24,
                          minY: 0,
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: 200,
                            getDrawingHorizontalLine: (_) => FlLine(
                              color: Theme.of(context).dividerColor,
                              strokeWidth: 1,
                            ),
                          ),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 6,
                                getTitlesWidget: (value, meta) {
                                  const labels = {
                                    0: '12am',
                                    6: '6am',
                                    12: '12pm',
                                    18: '6pm',
                                    24: '11pm',
                                  };
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      labels[value.toInt()] ?? '',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                interval: 200,
                                getTitlesWidget: (value, meta) => Text(
                                  '${value.toInt()}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: todaySpots,
                              isCurved: true,
                              color: const Color(0xFFFF7E00),
                              barWidth: 3,
                              isStrokeCapRound: true,
                              dotData: FlDotData(
                                show: true,
                                getDotPainter: (spot, _, _, _) =>
                                    FlDotCirclePainter(
                                      radius: 4,
                                      color: const Color(0xFFFF7E00),
                                      strokeWidth: 2,
                                      strokeColor: Colors.white,
                                    ),
                              ),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    const Color(
                                      0xFFFF7E00,
                                    ).withValues(alpha: 0.2),
                                    const Color(
                                      0xFFFF7E00,
                                    ).withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),

              const SizedBox(height: 24),

              // ── Calorie totals per day ───────────────────────────────
              _buildSectionTitle('Daily Calories', 'Last 7 days total kcal'),
              const SizedBox(height: 12),
              _buildCalorieSummaryList(context, dayStatsMap, dayKeys),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard({
    required BuildContext context,
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: color.withValues(alpha: 0.6), width: 3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required BuildContext context,
    required double height,
    required Widget child,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildCalorieSummaryList(
    BuildContext context,
    Map<String, _DayStats> dayStatsMap,
    List<String> dayKeys,
  ) {
    // Find max for proportional bars
    final maxCals = dayStatsMap.values
        .map((s) => s.totalCalories)
        .fold(0.0, (a, b) => a > b ? a : b);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: dayKeys.reversed.map((key) {
          final stats = dayStatsMap[key]!;
          final ratio = maxCals > 0 ? stats.totalCalories / maxCals : 0.0;
          final isLast = key == dayKeys.first;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    key,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: stats.mealCount > 0
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.35),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 7,
                      backgroundColor: Theme.of(context).dividerColor,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFF7E00),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 70,
                  child: Text(
                    stats.mealCount > 0
                        ? '${stats.totalCalories.toInt()} kcal'
                        : '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: stats.mealCount > 0
                          ? const Color(0xFFFF7E00)
                          : Theme.of(context).colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DayStats {
  int mealCount = 0;
  double totalCalories = 0;
}
