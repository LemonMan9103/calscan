import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RecordService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String? uid = FirebaseAuth.instance.currentUser?.uid;

  // Stream of all meals for a specific month
  Stream<QuerySnapshot> getMealsForMonth(DateTime month) {
    if (uid == null) return const Stream.empty();

    final startOfMonth = DateTime(month.year, month.month, 1);
    final nextMonth = DateTime(month.year, month.month + 1, 1);
    final endOfMonth = nextMonth.subtract(const Duration(seconds: 1));

    return _db
        .collection('users')
        .doc(uid)
        .collection('meals')
        .where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
        )
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // Future CRUD operations will be added here (Update, Delete)
  Future<void> deleteMeal(String mealId) async {
    if (uid == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('meals')
        .doc(mealId)
        .delete();
  }

  Future<void> addMeal(Map<String, dynamic> mealData) async {
    if (uid == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('meals')
        .add({
          ...mealData,
          'timestamp': mealData.containsKey('timestamp') ? mealData['timestamp'] : FieldValue.serverTimestamp(),
        });
  }

  Stream<QuerySnapshot> getMealsForLast7Days() {
    if (uid == null) return const Stream.empty();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    return _db
        .collection('users')
        .doc(uid)
        .collection('meals')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .orderBy('timestamp')
        .snapshots();
  }

  Stream<QuerySnapshot> getMealsForStreakCheck() {
    if (uid == null) return const Stream.empty();
    final start = DateTime.now().subtract(const Duration(days: 30));
    return _db
        .collection('users')
        .doc(uid)
        .collection('meals')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}
