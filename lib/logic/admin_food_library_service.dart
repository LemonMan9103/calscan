import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:calscan/logic/firestore_service.dart';
import 'package:calscan/logic/food_lookup_service.dart';
import 'package:image/image.dart' as img;

class AdminFoodLibraryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

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

  Future<String> uploadFoodImage({
    required File imageFile,
    required String foodKey,
    String? sourceMimeType,
    String? sourceName,
  }) async {
    await _assertAdmin();

    final key = _storageKey(foodKey);
    if (key.isEmpty) {
      throw StateError('Food key is needed before uploading image.');
    }

    final upload = await _prepareFoodImageUpload(
      imageFile,
      sourceMimeType: sourceMimeType,
      sourceName: sourceName,
    );
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ref = _storage.ref('food_images/$key/${upload.fileName}');
    final metadata = {'foodKey': key};
    if (uid != null) metadata['updatedBy'] = uid;

    await ref.putData(
      upload.bytes,
      SettableMetadata(
        contentType: upload.contentType,
        customMetadata: metadata,
      ),
    );

    return ref.getDownloadURL();
  }

  Future<_PreparedFoodImageUpload> _prepareFoodImageUpload(
    File imageFile, {
    String? sourceMimeType,
    String? sourceName,
  }) async {
    final raw = await imageFile.readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      final contentType = _imageContentType(sourceMimeType, sourceName);
      return _PreparedFoodImageUpload(
        bytes: raw,
        contentType: contentType,
        fileName: 'main.${_extensionForContentType(contentType)}',
      );
    }

    final oriented = img.bakeOrientation(decoded);
    const maxSide = 800;
    final longestSide = math.max(oriented.width, oriented.height);
    final resized = longestSide <= maxSide
        ? oriented
        : img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? maxSide : null,
            height: oriented.height > oriented.width ? maxSide : null,
            interpolation: img.Interpolation.average,
          );

    // resize before upload, keep storage not too big
    return _PreparedFoodImageUpload(
      bytes: Uint8List.fromList(img.encodeJpg(resized, quality: 82)),
      contentType: 'image/jpeg',
      fileName: 'main.jpg',
    );
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

  String _storageKey(String key) {
    return key
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _imageContentType(String? mimeType, String? name) {
    final normalizedMime = mimeType?.trim().toLowerCase();
    if (_supportedImageContentTypes.contains(normalizedMime)) {
      return normalizedMime!;
    }

    final extension = (name ?? '').split('.').last.trim().toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };
  }

  String _extensionForContentType(String contentType) {
    return switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      _ => 'jpg',
    };
  }

  static const _supportedImageContentTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif',
  };
}

class _PreparedFoodImageUpload {
  final Uint8List bytes;
  final String contentType;
  final String fileName;

  const _PreparedFoodImageUpload({
    required this.bytes,
    required this.contentType,
    required this.fileName,
  });
}
