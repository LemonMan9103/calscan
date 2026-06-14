import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:calscan/logic/crud_records.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _previousMonth() => setState(
    () => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1),
  );

  void _nextMonth() => setState(
    () => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1),
  );

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _currentMonth.year == now.year && _currentMonth.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Intake Records',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: () => showManualRecordDialog(context),
              icon: const Icon(Icons.add, size: 18, color: Colors.white),
              label: const Text('Add', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7E00),
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
          final allDocs = snapshot.hasData
              ? snapshot.data!.docs
              : <QueryDocumentSnapshot>[];

          // Filter by search query
          final docs = _searchQuery.isEmpty
              ? allDocs
              : allDocs.where((d) {
                  final name = (d['mealName'] as String? ?? '').toLowerCase();
                  return name.contains(_searchQuery.toLowerCase());
                }).toList();

          // Monthly totals
          double monthlyCalories = 0;
          for (var d in allDocs) {
            monthlyCalories += (d['calories'] as num).toDouble();
          }

          return Column(
            children: [
              _buildMonthNavigator(allDocs.length, monthlyCalories),
              _buildSearchBar(),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF7E00)),
                  ),
                )
              else if (docs.isEmpty)
                _buildEmptyState()
              else
                Expanded(child: _buildGroupedListView(docs)),
            ],
          );
        },
      ),
    );
  }

  // ── Month navigator ──────────────────────────────────────────────────────

  Widget _buildMonthNavigator(int mealCount, double totalCalories) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Color(0xFFFF7E00)),
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
                    '$mealCount meals logged',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  color: _isCurrentMonth
                      ? Colors.grey.shade300
                      : const Color(0xFFFF7E00),
                ),
                onPressed: _isCurrentMonth ? null : _nextMonth,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Search bar ───────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: 'Search meals...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHigh,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ── Grouped list ─────────────────────────────────────────────────────────

  Widget _buildGroupedListView(List<QueryDocumentSnapshot> docs) {
    // Group by date
    final Map<String, List<QueryDocumentSnapshot>> grouped = {};
    for (var doc in docs) {
      final date = (doc['timestamp'] as Timestamp).toDate();
      final dateKey = DateFormat('MMM dd, EEEE').format(date);
      grouped.putIfAbsent(dateKey, () => []).add(doc);
    }

    final sortedKeys = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: sortedKeys.length,
      itemBuilder: (context, index) {
        final dateKey = sortedKeys[index];
        final dayMeals = grouped[dateKey]!;
        double dailyTotal = dayMeals.fold(
          0.0,
          (acc, m) => acc + (m['calories'] as num).toDouble(),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Day header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateKey,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7E00).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${dailyTotal.toInt()} kcal',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF7E00),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Meal cards ──────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: dayMeals.asMap().entries.map((entry) {
                  final i = entry.key;
                  final meal = entry.value;
                  final isLast = i == dayMeals.length - 1;
                  return _buildMealRow(meal, isLast: isLast);
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMealRow(QueryDocumentSnapshot meal, {required bool isLast}) {
    final data = meal.data() as Map<String, dynamic>;
    final time = (meal['timestamp'] as Timestamp).toDate();
    final timeString = DateFormat.jm().format(time);
    final mealName = meal['mealName'] as String? ?? 'Unnamed';
    final portion = _mealPortionDescription(meal);
    final calories = (meal['calories'] as num).toInt();
    final protein = (data['protein'] as num?)?.toDouble() ?? 0.0;
    final carbs = (data['carbs'] as num?)?.toDouble() ?? 0.0;
    final fat = (data['fat'] as num?)?.toDouble() ?? 0.0;
    final hasMacros = protein + carbs + fat > 0;

    return Dismissible(
      key: Key(meal.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(isLast ? 16 : 0),
            bottomRight: Radius.circular(isLast ? 16 : 0),
            topLeft: Radius.zero,
            bottomLeft: Radius.zero,
          ),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Delete meal?'),
            content: Text('Remove "$mealName" from your records?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => _recordService.deleteMeal(meal.id),
      child: InkWell(
        onTap: () => showManualRecordDialog(
          context,
          mealId: meal.id,
          initialData: meal.data() as Map<String, dynamic>,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
          ),
          child: Row(
            children: [
              // Time column
              SizedBox(
                width: 52,
                child: Text(
                  timeString,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
              // Food icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF7E00).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.restaurant_menu,
                  color: Color(0xFFFF7E00),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              // Name + portion
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mealName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      portion,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    if (hasMacros) ...[
                      const SizedBox(height: 2),
                      Text(
                        'P ${protein.toInt()}g · C ${carbs.toInt()}g · F ${fat.toInt()}g',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Calories
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$calories',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF7E00),
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'kcal',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.edit_outlined,
                size: 17,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _mealPortionDescription(QueryDocumentSnapshot meal) {
    final data = meal.data() as Map<String, dynamic>;
    final rawItems = data['items'];
    if (rawItems is List && rawItems.isNotEmpty) {
      return rawItems
          .map((rawItem) {
            if (rawItem is! Map) return '';
            final name = rawItem['name']?.toString() ?? 'Food';
            final serving =
                rawItem['serving']?.toString() ??
                rawItem['portion']?.toString() ??
                '1 serving';
            return '$name ($serving)';
          })
          .where((item) => item.isNotEmpty)
          .join(' + ');
    }
    return data['portion']?.toString() ?? 'General';
  }

  // ── Empty state ──────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    final isSearching = _searchQuery.isNotEmpty;
    final theme = Theme.of(context);
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSearching ? Icons.search_off : Icons.receipt_long_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              isSearching
                  ? 'No meals match "$_searchQuery"'
                  : 'No records this month',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            if (!isSearching)
              Text(
                'Tap + Add to log your first meal',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
