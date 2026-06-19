import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:calscan/logic/offline_write.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> saveUserProfile({
    //utk save user profile
    required String name,
    required double weight,
    required double height,
    required int age,
    String? gender,
    required String activityLevel,
    required String goal,
    required int calorieTarget,
    DateTime? targetDate,
  }) async {
    if (uid == null) return;

    await _db.collection('users').doc(uid).set({
      //save
      'name': name,
      'weight': weight,
      'height': height,
      'age': age,
      ...gender == null ? {} : {'gender': gender},
      'activityLevel': activityLevel,
      'goal': goal,
      'calorieTarget': calorieTarget,
      if (targetDate != null) 'targetDate': Timestamp.fromDate(targetDate),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<DocumentSnapshot?> getUserProfile() async {
    // get user profile
    if (uid == null) return null;
    return await _db.collection('users').doc(uid).get();
  }

  Future<bool> isCurrentUserAdmin() async {
    // admin must come from firestore, dont trust email text
    final doc = await getUserProfile();
    final data = doc?.data() as Map<String, dynamic>?;
    return data?['role'] == 'admin';
  }

  Future<FirestoreWriteStatus> saveMeal({
    // save meal record
    required String mealName,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required String portion,
    DateTime? timestamp,
  }) async {
    if (uid == null) {
      throw StateError('You must be logged in to save a meal.');
    }

    final write = _db
        .collection('users')
        .doc(uid)
        .collection('meals')
        .doc()
        .set({
          'mealName': mealName,
          'calories': calories,
          'protein': protein,
          'carbs': carbs,
          'fat': fat,
          'portion': portion,
          'timestamp': timestamp ?? FieldValue.serverTimestamp(),
        });
    return waitForFirestoreWrite(write);
  }

  // Stream of today's meals
  Stream<QuerySnapshot> getTodayMeals() {
    if (uid == null) return const Stream.empty();

    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

    return _db
        .collection('users')
        .doc(uid)
        .collection('meals')
        .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
        .where('timestamp', isLessThanOrEqualTo: endOfDay)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}
