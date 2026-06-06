import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String? uid = FirebaseAuth.instance.currentUser?.uid;

  Future<void> saveUserProfile({
    //utk save user profile
    required String name,
    required double weight,
    required double height,
    required int age,
    required String activityLevel,
    required String goal,
    required int calorieTarget,
  }) async {
    if (uid == null) return;

    await _db.collection('users').doc(uid).set({
      //save
      'name': name,
      'weight': weight,
      'height': height,
      'age': age,
      'activityLevel': activityLevel,
      'goal': goal,
      'calorieTarget': calorieTarget,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<DocumentSnapshot?> getUserProfile() async {
    // get user profile
    if (uid == null) return null;
    return await _db.collection('users').doc(uid).get();
  }

  Future<void> saveMeal({
    // save meal record
    required String mealName,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required String portion,
    DateTime? timestamp,
  }) async {
    if (uid == null) return;

    await _db.collection('users').doc(uid).collection('meals').add({
      'mealName': mealName,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'portion': portion,
      'timestamp': timestamp ?? FieldValue.serverTimestamp(),
    });
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
