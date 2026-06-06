import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:calscan/logic/crud_records.dart';
import 'package:calscan/logic/mock.dart';
import 'package:calscan/home/manual_record.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  DateTime _currentMonth = DateTime.now();
  final RecordService _recordService = RecordService();

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
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
          'Intake Records',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: () async {
              await MockDataService().seedMockMeals();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mock data seeded successfully!')),
                );
              }
            },
            icon: const Icon(Icons.science_outlined, color: Colors.orange),
            tooltip: 'Seed Mock Data',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: () => showManualRecordDialog(context),
              icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.white),
              label: const Text('Add', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _recordService.getMealsForMonth(_currentMonth),
        builder: (context, snapshot) {
          int totalMeals = snapshot.hasData ? snapshot.data!.docs.length : 0;
          
          return Column(
            children: [
              _buildMonthNavigator(totalMeals),
              _buildSearchBar(),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'No records found for this month.\nStart logging meals to see them here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ),
                )
              else
                Expanded(
                  child: _buildGroupedListView(snapshot.data!.docs),
                ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildGroupedListView(List<QueryDocumentSnapshot> docs) {
    // 1. Group docs by date
    final Map<String, List<QueryDocumentSnapshot>> grouped = {};
    for (var doc in docs) {
      final date = (doc['timestamp'] as Timestamp).toDate();
      final dateKey = DateFormat('MMM dd, EEEE').format(date);
      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(doc);
    }

    final List<String> sortedKeys = grouped.keys.toList();
    // Keys are already sorted by stream ordering (descending timestamp)
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: sortedKeys.length,
      itemBuilder: (context, index) {
        final dateKey = sortedKeys[index];
        final dayMeals = grouped[dateKey]!;
        
        double dailyTotal = 0;
        for (var meal in dayMeals) {
          dailyTotal += (meal['calories'] as num).toDouble();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Header + Total
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateKey,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                  ),
                  Text(
                    '${dailyTotal.toInt()} kcal',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Meal List for the day
            ...dayMeals.map((meal) {
              final time = (meal['timestamp'] as Timestamp).toDate();
              final timeString = DateFormat.jm().format(time);
              
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                ),
                child: Row(
                  children: [
                    // Time instead of icon
                    SizedBox(
                      width: 80,
                      child: Text(
                        timeString,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meal['mealName'] ?? 'Unnamed',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Portion: ${meal['portion'] ?? 'General'}',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '-${(meal['calories'] as num).toInt()} kcal',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 16),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  Widget _buildMonthNavigator(int mealCount) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.orange),
                onPressed: _previousMonth,
              ),
              Column(
                children: [
                  Text(
                    DateFormat('MMMM yyyy').format(_currentMonth),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$mealCount meals',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.orange),
                onPressed: _nextMonth,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search meals...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}


