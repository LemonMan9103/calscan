# Esti
A Malaysian Food Calorie Estimator — Final Year Project (FYP)

## Overview
Esti is a Flutter mobile app that uses computer vision to detect Malaysian food from a camera photo and estimate its calorie content. The app is designed to help Malaysians track their daily calorie intake in a fast and convenient way.

## Features
- 📷 **Food Detection** — Scan a plate of food using your phone camera
- 🍛 **Malaysian Food Focused** — Detects 49 Malaysian food classes including nasi lemak, ayam goreng, roti canai, and more
- 🔢 **Calorie Estimation** — Estimates calories based on detected food with S/M/L portion sizing
- 📊 **Daily Tracking** — Logs food intake and tracks daily calorie goals
- 📈 **Statistics** — View calorie trends over time
- 👤 **Personalized Goals** — Calorie targets based on user profile (age, weight, height, activity level)
- 🔥 **Firebase Integration** — User data and food logs stored in Firebase Firestore

## Tech Stack
| Component | Technology |
|---|---|
| Frontend | Flutter (Dart) |
| AI Model | YOLOv11 (Ultralytics) |
| Model Format | TFLite (float32) |
| Backend | Firebase Firestore |
| Training Environment | Google Colab |
| Dataset Management | Roboflow |

## AI Model
- **Architecture:** YOLOv11n (nano)
- **Classes:** 49 Malaysian food classes
- **Training Dataset:** ~3,500 images sourced from Roboflow public datasets and manual collection, annotated via Roboflow
- **mAP50:** 0.594
- **Input Size:** 640×640
- **Export Format:** TFLite float32

### Detection Strategy
The app uses a hybrid two-tier detection approach:
- **Whole Dish Detection** — Fixed presentation dishes (e.g. Nasi Lemak, Char Kway Teow) detected as one unit with fixed base calories
- **Component Detection** — Individual components (e.g. Nasi Putih, Ayam Goreng, Telur Rebus) detected separately and summed for mixed plate scenarios like Nasi Berlauk

### Calorie Calculation
```
Final Calories = Base Calories × Portion Multiplier

Portion Multipliers:
  S (Small)  = × 0.8
  M (Medium) = × 1.0
  L (Large)  = × 1.3
```

Cooking method modifiers are embedded directly into base calorie values per class.

## Food Classes
The model detects 49 classes including:

**Whole Dishes:** Nasi Lemak, Nasi Kerabu, Nasi Goreng, Nasi Dagang, Mee Goreng, Char Kway Teow, Kway Teow Goreng, Patin Tempoyak, Burger, Pizza, Steak, Cendol

**Components:** Nasi Putih, Ayam Goreng, Ayam Masak Merah, Ayam Masak Lemak, Ayam Masak Kicap, Ayam Masak Kurma, Ayam Goreng Kunyit, Ayam Bakar, Rendang Daging, Gulai Ikan Tongkol, Ikan Goreng, Keli Goreng, Udang, Telur Rebus, Telur Goreng, Telur Dadar, Telur Masin, Tempe Goreng, Kangkung Goreng, Sambal, Sambal Ikan Bilis, Ikan Bilis Goreng, Kacang Goreng, Timun, Kentang, Paru Goreng, Daging Bakar

**Snacks:** Roti Canai, Karipap, Pisang Goreng, Apam Balik, Kaya Toast, Satay, Popia Goreng, Solok Lada

## Project Structure
```
calscan/
├── lib/
│   ├── home/
│   │   ├── camera.dart                 # Food detection camera
│   │   ├── nutrition_label_camera.dart # OCR label camera
│   │   ├── scan_mode_sheet.dart        # Scan mode chooser sheet
│   │   ├── scan_result_page.dart       # Detection results
│   │   ├── manual_record.dart          # Manual meal entry
│   │   ├── homepage.dart               # Home screen
│   │   ├── records.dart                # Food log records
│   │   ├── progress.dart               # Progress / stats
│   │   ├── main_wrapper.dart           # Bottom-nav shell
│   │   └── settings_page.dart          # App settings
│   ├── logic/
│   │   ├── recognition_service.dart    # TFLite inference
│   │   ├── food_lookup_service.dart    # Calorie lookup table
│   │   ├── nutrition_label_parser.dart # OCR text parser
│   │   ├── calorie_calculation.dart    # Portion math
│   │   ├── crud_records.dart           # Firestore CRUD
│   │   ├── firestore_service.dart      # Firestore helpers
│   │   ├── offline_write.dart          # Offline queue
│   │   └── saved_food_service.dart     # Saved packaged foods
│   ├── profile/
│   │   ├── login_page.dart
│   │   ├── profile_setup.dart
│   │   └── goal_setup.dart
│   ├── theme/
│   │   ├── app_theme.dart
│   │   └── theme_controller.dart
│   └── main.dart
├── assets/
│   ├── food_lookup.json       # Calorie lookup table (49 classes)
│   └── best_float32.tflite   # Trained YOLOv11 TFLite model
├── android/
└── pubspec.yaml
```

## Setup
1. Clone the repository
2. Run `flutter pub get`
3. Add `google-services.json` to `android/app/` (Firebase config — not included in repo)
4. Run `flutter run`

## Dataset
- ~3,500 images sourced from Roboflow public datasets and supplemented with manual collection
- Annotated using Roboflow (Object Detection project)
- Augmentation: horizontal flip, ±15° rotation, brightness variation
- Split: 88% train / 8% validation / 4% test

## Known Limitations
- Calorie estimation accuracy: ±20–30% (on par with commercial apps like MyFitnessPal)
- Weak detection on classes with fewer training images (Daging Bakar, Solok Lada)
- Ingredients blended inside sauces (e.g. anchovies inside sambal) are not separately detectable
- Model trained on yolo11n (nano) — accuracy can be improved with yolo11s (small) in future

## Future Work
- Improve weak classes with more training data
- Upgrade to YOLOv11s for better accuracy
- Add texture/cooking method CNN classifier
- Integrate nutritional breakdown (protein, carbs, fat)
- Add meal planning and dietary recommendations

## Author
Developed as a Final Year Project at UNIZA.
