import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:calscan/logic/firestore_service.dart';
import 'package:calscan/logic/food_lookup_service.dart';

class AdminFoodLibraryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _foods =>
      _db.collection('food_library');

  Future<Map<String, FoodEntry>> fetchAdminFoods() async {
    final snapshot = await _foods.get();
    return {
      for (final doc in snapshot.docs)
        doc.id: FoodEntry.fromMap(doc.id, doc.data(), source: 'admin'),
    };
  }

  Future<void> saveFood(FoodEntry food) async {
    await _assertAdmin();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final docRef = _foods.doc(food.key);
    final existing = await docRef.get();

    await docRef.set({
      ...food.toAdminMap(),
      'source': 'admin',
      'search_name': food.displayName.toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      if (!existing.exists) 'createdBy': uid,
    }, SetOptions(merge: true));
  }

  Future<void> hideFood(FoodEntry food) async {
    await saveFood(
      FoodEntry(
        key: food.key,
        displayName: food.displayName,
        category: food.category,
        baseCalories: food.baseCalories,
        cookingModifier: food.cookingModifier,
        description: food.description,
        baseProtein: food.baseProtein,
        baseCarbs: food.baseCarbs,
        baseFat: food.baseFat,
        archetypeId: food.archetypeId,
        imageUrl: food.imageUrl,
        source: 'admin',
        isActive: false,
      ),
    );
  }

  Future<void> deleteOverride(String key) async {
    await _assertAdmin();
    await _foods.doc(key).delete();
  }

  Future<void> _assertAdmin() async {
    // admin write also check here, dont only trust page button
    final isAdmin = await FirestoreService().isCurrentUserAdmin();
    if (!isAdmin) {
      throw StateError('Only admin can change food library.');
    }
  }

  String keyFromName(String name) {
    final key = name
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return key.isEmpty ? 'Food_${DateTime.now().millisecondsSinceEpoch}' : key;
  }
}
