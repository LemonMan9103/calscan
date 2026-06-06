import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

//mock datas only
class MockDataService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String? uid = FirebaseAuth.instance.currentUser?.uid;

  Future<void> seedMockMeals() async {
    if (uid == null) return;

    final mealsCollection = _db
        .collection('users')
        .doc(uid)
        .collection('meals');
    final now = DateTime.now();

    final List<Map<String, dynamic>> mockMeals = [
      {
        'mealName': 'Nasi Lemak Ayam Goreng',
        'calories': 680.0,
        'portion': '...',
        'timestamp': Timestamp.fromDate(now.subtract(const Duration(hours: 4))),
        'protein': 18.0,
        'carbs': 85.0,
        'fat': 28.0,
      },
      {
        'mealName': 'Char Kway Teow',
        'calories': 740.0,
        'portion': '...',
        'timestamp': Timestamp.fromDate(
          now.subtract(const Duration(hours: 18)),
        ),
        'protein': 15.0,
        'carbs': 90.0,
        'fat': 38.0,
      },
      {
        'mealName': 'Chicken Rice',
        'calories': 620.0,
        'portion': '...',
        'timestamp': Timestamp.fromDate(
          now.subtract(const Duration(days: 1, hours: 2)),
        ),
        'protein': 30.0,
        'carbs': 65.0,
        'fat': 22.0,
      },
      {
        'mealName': 'Pisang Goreng (3 pcs)',
        'calories': 350.0,
        'portion': '...',
        'timestamp': Timestamp.fromDate(
          now.subtract(const Duration(days: 1, hours: 5)),
        ),
        'protein': 3.0,
        'carbs': 48.0,
        'fat': 18.0,
      },
      {
        'mealName': 'Roti Canai with Lentil Curry',
        'calories': 420.0,
        'portion': '...',
        'timestamp': Timestamp.fromDate(
          now.subtract(const Duration(days: 2, hours: 1)),
        ),
        'protein': 12.0,
        'carbs': 55.0,
        'fat': 16.0,
      },
    ];

    for (var meal in mockMeals) {
      await mealsCollection.add(meal);
    }
  }
}
