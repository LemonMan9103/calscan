# Esti

Esti is a Flutter Final Year Project app for camera-assisted calorie estimation and meal tracking. It focuses on Malaysian foods, manual food logging, nutrition-label OCR, weekly goal progress, and admin-managed food library data.

## Current Features

- Food scan camera using a bundled YOLO TFLite recognition model.
- Portion helper using a bundled YOLO segmentation model for plate/tapau/rice-style meals.
- Nutrition label OCR using Google ML Kit text recognition.
- Manual meal entry with custom foods and editable records.
- Offline Firestore writes with later sync.
- Weekly goal progress and target date support.
- Dark theme support.
- Admin dashboard for food library management.
- Admin food image upload to Firebase Storage.

## Models

### Food Recognition

- File: `lib/assets/best_float32.tflite`
- Input: `1 x 640 x 640 x 3`
- Output: `1 x 65 x 8400`
- Classes: `61`
- Labels are hardcoded in `lib/logic/recognition_service.dart`.
- Bundled food lookup entries in `lib/assets/food_lookup.json` must match the model labels exactly.

### Portion Segmentation

- File: `lib/assets/portion_model_float32.tflite`
- Labels file: `lib/assets/portion_labels.txt`
- Classes:
  - `curry_chicken`
  - `fried_chicken`
  - `fried_egg`
  - `fried_vegetables`
  - `plate`
  - `rice`
  - `tapau_box`

The portion model does not calculate calories directly. It estimates visible food area against the plate/tapau reference mask, then the app suggests one of the existing portion choices.

## Admin Setup

Admin access is controlled through the user document:

```text
users/<uid>.role = "admin"
```

Admin can edit foods in Firestore collection:

```text
food_library
```

Food images are uploaded to Firebase Storage:

```text
food_images/<foodKey>/main.jpg
```

## Firebase Rules Needed

Firestore:

```js
match /users/{userId}/{document=**} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}

match /food_library/{foodId} {
  allow read: if request.auth != null;
  allow write: if request.auth != null
    && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == "admin";
}
```

Storage:

```js
match /food_images/{foodKey}/{fileName} {
  allow read: if request.auth != null;
  allow write: if request.auth != null
    && firestore.get(/databases/(default)/documents/users/$(request.auth.uid)).data.role == "admin";
}
```

## Setup

1. Run `flutter pub get`.
2. Add Firebase Android config to `android/app/google-services.json`.
3. Generate or provide `lib/firebase_options.dart`.
4. Set at least one admin user in Firestore.
5. Run `flutter run`.

## Useful Checks

```bash
flutter analyze
flutter test
```

Modern Android APK build:

```bash
flutter build apk --release --split-per-abi
```

## Notes

- The package/project name remains `calscan` internally to avoid Firebase and Android package churn.
- User-facing branding should say Esti.
- Training notebooks and temporary preview images are intentionally ignored from Git.
