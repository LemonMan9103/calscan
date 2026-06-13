import 'package:calscan/logic/nutrition_label_parser.dart';
import 'package:calscan/logic/offline_write.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SavedPackagedFood {
  final String id;
  final String name;
  final double calories;
  final CalorieBasis calorieBasis;
  final String serving;

  const SavedPackagedFood({
    required this.id,
    required this.name,
    required this.calories,
    required this.calorieBasis,
    required this.serving,
  });

  factory SavedPackagedFood.fromDocument(DocumentSnapshot document) {
    final data = document.data() as Map<String, dynamic>;
    return SavedPackagedFood(
      id: document.id,
      name: data['name']?.toString() ?? 'Packaged food',
      calories: (data['calories'] as num?)?.toDouble() ?? 0,
      calorieBasis: CalorieBasis.values.firstWhere(
        (basis) => basis.name == data['calorieBasis'],
        orElse: () => CalorieBasis.unknown,
      ),
      serving: data['serving']?.toString() ?? '1 serving',
    );
  }
}

class SavedFoodService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Stream<List<SavedPackagedFood>> watchPackagedFoods() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('users')
        .doc(uid)
        .collection('savedFoods')
        .orderBy('lastUsedAt', descending: true)
        .limit(30)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(SavedPackagedFood.fromDocument)
              .toList(growable: false),
        );
  }

  Future<FirestoreWriteStatus> savePackagedFood({
    required String name,
    required double calories,
    required CalorieBasis calorieBasis,
    required String serving,
  }) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('You must be logged in to save a packaged food.');
    }
    final id = _documentId(name);
    final write = _db
        .collection('users')
        .doc(uid)
        .collection('savedFoods')
        .doc(id)
        .set({
          'name': name,
          'calories': calories,
          'calorieBasis': calorieBasis.name,
          'serving': serving,
          'lastUsedAt': Timestamp.now(),
        }, SetOptions(merge: true));
    return waitForFirestoreWrite(write);
  }

  String _documentId(String name) {
    final normalized = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'packaged-food' : normalized;
  }
}
