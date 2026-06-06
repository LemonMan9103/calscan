import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:calscan/logic/crud_records.dart';
import 'package:calscan/logic/firestore_service.dart';
import 'package:intl/intl.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  final RecordService _recordService = RecordService();
  final FirestoreService _firestoreService = FirestoreService();
  int _calorieTarget = 2000;

  @override
  void initState() {
    super.initState();
    _firestoreService.getUserProfile().then((doc) {
      if (doc != null && doc.exists && mounted) {
        setState(() {
          _calorieTarget = (doc['calorieTarget'] as num?)?.toInt() ?? 2000;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Progress Stats',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _recordService.getMealsForLast7Days(),
        builder: (context, snapshot7) {
          return StreamBuilder<QuerySnapshot>(
            stream: _recordService.getMealsForStreakCheck(),
            builder: (context, snapshotStreak) {
              final docs7 = snapshot7.data?.docs ?? [];
              final streakDocs = snapshotStreak.data?.docs ?? [];

              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);

              // Today's meals
              final todayMeals = docs7.where((d) {
                final ts = (d['timestamp'] as Timestamp?)?.toDate();
                if (ts == null) return false;
                return DateTime(ts.year, ts.month, ts.day) == today;
              }).toList();

              // Calorie goal progress
              double todayCalories = todayMeals.fold(0.0, (s, d) => s + (d['calories'] as num).toDouble());
              double goalProgress = (todayCalories / _calorieTarget).clamp(0.0, 1.0);

              // Macros
              double totalProtein = todayMeals.fold(0.0, (s, d) => s + ((d['protein'] as num?)?.toDouble() ?? 0));
              double totalCarbs = todayMeals.fold(0.0, (s, d) => s + ((d['carbs'] as num?)?.toDouble() ?? 0));
              double totalFat = todayMeals.fold(0.0, (s, d) => s + ((d['fat'] as num?)?.toDouble() ?? 0));

              // Meals per day (last 7 days)
              final Map<String, int> mealsPerDay = {};
              for (int i = 6; i >= 0; i--) {
                final day = today.subtract(Duration(days: i));
                mealsPerDay[DateFormat('MM/dd').format(day)] = 0;
              }
              for (var doc in docs7) {
                final ts = (doc['timestamp'] as Timestamp?)?.toDate();
                if (ts == null) continue;
                final key = DateFormat('MM/dd').format(ts);
                if (mealsPerDay.containsKey(key)) {
                  mealsPerDay[key] = mealsPerDay[key]! + 1;
                }
              }
              final dayKeys = mealsPerDay.keys.toList();
              final maxMeals = mealsPerDay.values.fold(0, (a, b) => a > b ? a : b).toDouble();

              // Avg meals per day
              double avgMeals = docs7.length / 7;

              // Streak
              final Set<String> datesWithMeals = {};
              for (var doc in streakDocs) {
                final ts = (doc['timestamp'] as Timestamp?)?.toDate();
                if (ts == null) continue;
                datesWithMeals.add(DateFormat('yyyy-MM-dd').format(ts));
              }
              int streak = 0;
              for (int i = 0; i <= 30; i++) {
                final day = today.subtract(Duration(days: i));
                if (datesWithMeals.contains(DateFormat('yyyy-MM-dd').format(day))) {
                  streak++;
                } else {
                  break;
                }
              }

              // Calorie by time of day (today)
              final List<FlSpot> calorieSpots = todayMeals
                  .map((d) {
                    final ts = (d['timestamp'] as Timestamp?)?.toDate();
                    if (ts == null) return null;
                    return FlSpot(
                      ts.hour + ts.minute / 60.0,
                      (d['calories'] as num).toDouble(),
                    );
                  })
                  .whereType<FlSpot>()
                  .toList()
                ..sort((a, b) => a.x.compareTo(b.x));

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Streak + Avg cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: 'Current Streak',
                            value: '$streak Days',
                            subtitle: streak > 0 ? 'Keep it up!' : 'Log a meal today!',
                            icon: Icons.local_fire_department,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Avg. Meals',
                            value: avgMeals.toStringAsFixed(1),
                            subtitle: 'per day (7d)',
                            icon: Icons.restaurant,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Calorie goal progress
                    const Text(
                      "Today's Calorie Goal",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _buildChartContainer(
                      height: 80,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${todayCalories.toInt()} kcal',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                '/ $_calorieTarget kcal',
                                style: const TextStyle(color: Colors.grey, fontSize: 14),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: goalProgress,
                              minHeight: 12,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                goalProgress >= 1.0 ? Colors.green : Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Macros breakdown
                    const Text(
                      "Today's Macros",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildMacroCard('Protein', totalProtein, Colors.blue)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildMacroCard('Carbs', totalCarbs, Colors.amber)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildMacroCard('Fat', totalFat, Colors.redAccent)),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Meals per day bar chart
                    const Text(
                      'Meals per Day (Last 7 Days)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _buildChartContainer(
                      height: 200,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: maxMeals < 1 ? 5 : maxMeals + 1,
                          barTouchData: BarTouchData(enabled: false),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx < 0 || idx >= dayKeys.length) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(dayKeys[idx], style: const TextStyle(fontSize: 10)),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                interval: 1,
                                getTitlesWidget: (value, meta) =>
                                    Text(value.toInt().toString(), style: const TextStyle(fontSize: 10)),
                              ),
                            ),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          barGroups: List.generate(dayKeys.length, (i) {
                            return BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: mealsPerDay[dayKeys[i]]!.toDouble(),
                                  color: Colors.orange,
                                  width: 16,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Calorie intake by time of day
                    const Text(
                      'Calorie Intake Distribution',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Today's calories by time of day",
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    _buildChartContainer(
                      height: 250,
                      child: calorieSpots.isEmpty
                          ? const Center(child: Text('No meals logged today', style: TextStyle(color: Colors.grey)))
                          : LineChart(
                              LineChartData(
                                minX: 0,
                                maxX: 24,
                                gridData: const FlGridData(show: true, drawVerticalLine: false),
                                titlesData: FlTitlesData(
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      interval: 4,
                                      getTitlesWidget: (value, meta) {
                                        const labels = {0: '12am', 4: '4am', 8: '8am', 12: '12pm', 16: '4pm', 20: '8pm', 24: '11pm'};
                                        final text = labels[value.toInt()] ?? '';
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Text(text, style: const TextStyle(fontSize: 10)),
                                        );
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 40,
                                      getTitlesWidget: (value, meta) =>
                                          Text(value.toInt().toString(), style: const TextStyle(fontSize: 10)),
                                    ),
                                  ),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                ),
                                borderData: FlBorderData(show: false),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: calorieSpots,
                                    isCurved: true,
                                    color: Colors.orange,
                                    barWidth: 4,
                                    isStrokeCapRound: true,
                                    dotData: const FlDotData(show: true),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      color: Colors.orange.withValues(alpha: 0.1),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildMacroCard(String label, double grams, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '${grams.toStringAsFixed(1)}g',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildChartContainer({required double height, required Widget child}) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
