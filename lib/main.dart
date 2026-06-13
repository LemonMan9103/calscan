import 'package:flutter/material.dart';
import 'package:calscan/profile/login_page.dart';
import 'package:calscan/home/main_wrapper.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:calscan/firebase_options.dart';
import 'package:calscan/logic/food_lookup_service.dart';
import 'package:calscan/theme/app_theme.dart';
import 'package:calscan/theme/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FoodLookupService().load(); // pre-load calorie lookup table
  final themeController = await ThemeController.load();
  runApp(MyApp(themeController: themeController));
}

class MyApp extends StatefulWidget {
  final ThemeController themeController;

  const MyApp({super.key, required this.themeController});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Stored once so MaterialApp.home never gets a new widget instance on theme
  // changes — that was resetting the navigator stack on every toggle.
  late final Widget _home;

  @override
  void initState() {
    super.initState();
    widget.themeController.addListener(_onThemeChanged);
    _home = StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.hasData
            ? MainWrapper(themeController: widget.themeController)
            : const LoginPage();
      },
    );
  }

  @override
  void didUpdateWidget(covariant MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeController != widget.themeController) {
      oldWidget.themeController.removeListener(_onThemeChanged);
      widget.themeController.addListener(_onThemeChanged);
    }
  }

  @override
  void dispose() {
    widget.themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Esti',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: widget.themeController.themeMode,
      home: _home,
    );
  }
}
