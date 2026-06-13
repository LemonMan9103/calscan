import 'dart:async';

import 'package:flutter/foundation.dart';

enum FirestoreWriteStatus { synced, queued }

/// Live count of writes queued offline and not yet confirmed by Firestore.
final pendingWritesNotifier = ValueNotifier<int>(0);

Future<FirestoreWriteStatus> waitForFirestoreWrite(
  Future<void> write, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    await write.timeout(timeout);
    return FirestoreWriteStatus.synced;
  } on TimeoutException {
    pendingWritesNotifier.value++;
    // Firestore has accepted the write into its local queue. Decrement the
    // counter when the write eventually reaches the server.
    unawaited(
      write.then((_) {
        pendingWritesNotifier.value =
            (pendingWritesNotifier.value - 1).clamp(0, 9999);
      }).catchError((Object _) {
        pendingWritesNotifier.value =
            (pendingWritesNotifier.value - 1).clamp(0, 9999);
      }),
    );
    return FirestoreWriteStatus.queued;
  }
}
