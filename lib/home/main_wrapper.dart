import 'package:flutter/material.dart';
import 'package:calscan/home/homepage.dart';
import 'package:calscan/home/settings_page.dart';
import 'package:calscan/home/records.dart';
import 'package:calscan/home/progress.dart';
import 'package:calscan/home/camera.dart';
import 'package:calscan/home/nutrition_label_camera.dart';
import 'package:calscan/home/nutrition_page.dart';
import 'package:calscan/logic/firestore_service.dart';
import 'package:calscan/logic/food_lookup_service.dart';
import 'package:calscan/logic/offline_write.dart';
import 'package:calscan/profile/profile_setup.dart';
import 'package:calscan/theme/theme_controller.dart';

class MainWrapper extends StatefulWidget {
  final ThemeController? themeController;
  final String? userName;
  final int? calorieTarget;
  final int? age;
  final double? weight;
  final double? height;
  final String? activityLevel;
  final String? goal;

  const MainWrapper({
    super.key,
    this.themeController,
    this.userName,
    this.calorieTarget,
    this.age,
    this.weight,
    this.height,
    this.activityLevel,
    this.goal,
  });

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _scanExpanded = false;

  void _closeScan() => setState(() => _scanExpanded = false);

  late String _userName;
  late int _calorieTarget;
  late int _age;
  late double _weight;
  late double _height;
  late String _gender;
  late String _activityLevel;
  late String _goal;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _initUserData();
  }

  Future<void> _initUserData() async {
    // If data is passed in (from Setup), use it
    if (widget.userName != null) {
      _userName = widget.userName!;
      _calorieTarget = widget.calorieTarget!;
      _age = widget.age!;
      _weight = widget.weight!;
      _height = widget.height!;
      _gender = '';
      _activityLevel = widget.activityLevel!;
      _goal = widget.goal!;
      _isAdmin = await FirestoreService().isCurrentUserAdmin();
      await FoodLookupService().refreshRemoteEntries();
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Otherwise, fetch from Firestore
    try {
      final doc = await FirestoreService().getUserProfile();
      if (doc != null && doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _userName = data['name'] ?? 'Guest';
        _calorieTarget = data['calorieTarget'] ?? 2000;
        _age = data['age'] ?? 25;
        _weight = (data['weight'] as num?)?.toDouble() ?? 65.0;
        _height = (data['height'] as num?)?.toDouble() ?? 170.0;
        _gender = data['gender'] ?? '';
        _activityLevel = data['activityLevel'] ?? 'Sedentary';
        _goal = data['goal'] ?? 'custom';
        // only show admin tools if firestore say admin
        _isAdmin = data['role'] == 'admin';
        await FoodLookupService().refreshRemoteEntries();
        if (mounted) setState(() => _isLoading = false);
      } else {
        // Profile missing! Redirect back to setup
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ProfileSetupPage()),
          );
        }
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      _userName = 'Guest';
      _calorieTarget = 2000;
      _age = 25;
      _weight = 65.0;
      _height = 170.0;
      _gender = '';
      _activityLevel = 'Sedentary';
      _goal = 'custom';
      _isAdmin = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final List<Widget> pages = [
      HomePage(userName: _userName, calorieTarget: _calorieTarget),
      const ProgressPage(),
      const RecordsPage(),
      SettingsPage(
        themeController: widget.themeController ?? ThemeController.instance,
        userName: _userName,
        calorieTarget: _calorieTarget,
        age: _age,
        weight: _weight,
        height: _height,
        gender: _gender,
        activityLevel: _activityLevel,
        goal: _goal,
        isAdmin: _isAdmin,
      ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _selectedIndex, children: pages),
          IgnorePointer(
            ignoring: !_scanExpanded,
            child: AnimatedOpacity(
              opacity: _scanExpanded ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: _closeScan,
                child: Container(color: Colors.black54),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 52,
            child: IgnorePointer(
              ignoring: !_scanExpanded,
              child: AnimatedOpacity(
                opacity: _scanExpanded ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: AnimatedSlide(
                  offset: _scanExpanded ? Offset.zero : const Offset(0, 0.4),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildScanOption(
                        icon: Icons.menu_book_rounded,
                        label: 'Food Library',
                        colors: const [Color(0xFF30C060), Color(0xFF059669)],
                        onTap: () {
                          _closeScan();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NutritionPage(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 18),
                      _buildScanOption(
                        icon: Icons.restaurant_rounded,
                        label: 'Scan Meal',
                        colors: const [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
                        onTap: () {
                          _closeScan();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CameraPage(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 18),
                      _buildScanOption(
                        icon: Icons.document_scanner_rounded,
                        label: 'Scan Label',
                        colors: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        onTap: () {
                          _closeScan();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NutritionLabelCameraPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<int>(
            valueListenable: pendingWritesNotifier,
            builder: (_, count, child) {
              if (count == 0) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(
                  vertical: 5,
                  horizontal: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$count ${count == 1 ? 'write' : 'writes'} pending sync',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          BottomAppBar(
            color: Theme.of(context).colorScheme.surface,
            shape: const CircularNotchedRectangle(),
            notchMargin: 8,
            child: SizedBox(
              height: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(0, Icons.home_outlined, 'Home'),
                  _buildNavItem(1, Icons.show_chart, 'Progress'),
                  const SizedBox(width: 48),
                  _buildNavItem(2, Icons.description_outlined, 'Records'),
                  _buildNavItem(3, Icons.settings_outlined, 'Settings'),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: GestureDetector(
        onTap: () => setState(() => _scanExpanded = !_scanExpanded),
        child: Container(
          height: 64,
          width: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: _scanExpanded
                  ? const [Color(0xFF6B7280), Color(0xFF4B5563)]
                  : const [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
            ),
            boxShadow: [
              BoxShadow(
                color: (_scanExpanded ? Colors.black : const Color(0xFFFF4B2B))
                    .withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              _scanExpanded ? Icons.close : Icons.camera_alt,
              key: ValueKey(_scanExpanded),
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildScanOption({
    required IconData icon,
    required String label,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.last.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_scanExpanded) _closeScan();
        setState(() => _selectedIndex = index);
      },
      child: SizedBox(
        width: 68,
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? activeColor : inactiveColor),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
