import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web not configured');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Platform not supported');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDJAFL6hUW3jygEc7FUTvnhQLu1Yy7cKbg',
    appId: '1:1050012405625:android:013fa8885f36db609c29a8',
    messagingSenderId: '1050012405625',
    projectId: 'calscan-34026',
    storageBucket: 'calscan-34026.firebasestorage.app',
  );
}
