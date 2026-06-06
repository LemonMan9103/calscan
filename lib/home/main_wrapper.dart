import 'package:flutter/material.dart';
import 'package:calscan/home/homepage.dart';
import 'package:calscan/home/settings_page.dart';
import 'package:calscan/home/camera.dart';
import 'package:calscan/home/records.dart';
import 'package:calscan/home/progress.dart';
import 'package:calscan/logic/firestore_service.dart';
import 'package:calscan/profile/profile_setup.dart';

class MainWrapper extends StatefulWidget {
  final String? userName;
  final int? calorieTarget;
  final int? age;
  final double? weight;
  final double? height;
  final String? activityLevel;
  final String? goal;

  const MainWrapper({
    super.key,
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
  
  late String _userName;
  late int _calorieTarget;
  late int _age;
  late double _weight;
  late double _height;
  late String _activityLevel;
  late String _goal;

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
      _activityLevel = widget.activityLevel!;
      _goal = widget.goal!;
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
        _activityLevel = data['activityLevel'] ?? 'Sedentary';
        _goal = data['goal'] ?? 'custom';
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
      _activityLevel = 'Sedentary';
      _goal = 'custom';
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final List<Widget> pages = [
      HomePage(userName: _userName, calorieTarget: _calorieTarget),
      const ProgressPage(),
      const RecordsPage(),
      SettingsPage(
        userName: _userName,
        calorieTarget: _calorieTarget,
        age: _age,
        weight: _weight,
        height: _height,
        activityLevel: _activityLevel,
        goal: _goal,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_outlined, 'Home'),
              _buildNavItem(1, Icons.show_chart, 'Progress'),
              const SizedBox(width: 48), // Space for FAB
              _buildNavItem(2, Icons.description_outlined, 'Records'),
              _buildNavItem(3, Icons.settings_outlined, 'Settings'),
            ],
          ),
        ),
      ),
      floatingActionButton: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CameraPage()),
          );
        },
        child: Container(
          height: 64,
          width: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF4B2B).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.camera_alt, color: Colors.white, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isSelected ? const Color(0xFFFF4B2B) : Colors.grey,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? const Color(0xFFFF4B2B) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
