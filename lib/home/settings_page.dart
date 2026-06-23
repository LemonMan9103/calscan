import 'package:calscan/admin/admin_dashboard_page.dart';
import 'package:calscan/logic/calorie_calculation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:calscan/profile/goal_setup.dart';
import 'package:calscan/profile/profile_setup.dart';
import 'package:calscan/profile/login_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calscan/theme/theme_controller.dart';

class SettingsPage extends StatefulWidget {
  final ThemeController themeController;
  final String userName;
  final int calorieTarget;
  final int age;
  final double weight;
  final double height;
  final String gender;
  final String activityLevel;
  final String goal;
  final bool isAdmin;

  const SettingsPage({
    super.key,
    required this.themeController,
    required this.userName,
    required this.calorieTarget,
    required this.age,
    required this.weight,
    required this.height,
    required this.gender,
    required this.activityLevel,
    required this.goal,
    required this.isAdmin,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _userName;
  late int _calorieTarget;
  late int _age;
  late double _weight;
  late double _height;
  late String _gender;
  late String _activityLevel;
  late String _goal;
  late bool _isAdmin;

  ThemeController get themeController => widget.themeController;
  String get userName => _userName;
  int get calorieTarget => _calorieTarget;
  int get age => _age;
  double get weight => _weight;
  double get height => _height;
  String get gender => _gender;
  String get activityLevel => _activityLevel;
  String get goal => _goal;
  bool get isAdmin => _isAdmin;

  @override
  void initState() {
    super.initState();
    _loadFromWidget();
  }

  void _loadFromWidget() {
    _userName = widget.userName;
    _calorieTarget = widget.calorieTarget;
    _age = widget.age;
    _weight = widget.weight;
    _height = widget.height;
    _gender = widget.gender;
    _activityLevel = widget.activityLevel;
    _goal = widget.goal;
    _isAdmin = widget.isAdmin;
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
      }
    }
  }

  Future<void> _openProfileEditor(BuildContext context) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileSetupPage(
          initialName: userName,
          initialAge: age,
          initialWeight: weight,
          initialHeight: height,
          initialGender: _profileGenderLabel(gender),
          initialActivityLevel: activityLevel,
          editOnly: true,
        ),
      ),
    );

    if (saved == true && context.mounted) {
      await _refreshProfile();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    }
  }

  Future<void> _refreshProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data();
    if (data == null || !mounted) return;

    setState(() {
      _userName = data['name']?.toString() ?? _userName;
      _calorieTarget =
          (data['calorieTarget'] as num?)?.toInt() ?? _calorieTarget;
      _age = (data['age'] as num?)?.toInt() ?? _age;
      _weight = (data['weight'] as num?)?.toDouble() ?? _weight;
      _height = (data['height'] as num?)?.toDouble() ?? _height;
      _gender = data['gender']?.toString() ?? _gender;
      _activityLevel = data['activityLevel']?.toString() ?? _activityLevel;
      _goal = data['goal']?.toString() ?? _goal;
      _isAdmin = data['role'] == 'admin';
    });
  }

  void _openGoalSetup(BuildContext context) {
    final profileGender = _genderFromProfile(gender);
    final bmr = CalorieCalculator.calculateBMR(
      weightKg: weight,
      heightCm: height,
      age: age,
      gender: profileGender,
    );
    final tdee = CalorieCalculator.calculateTDEE(
      bmr,
      _activityMultiplier(activityLevel),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GoalSetupPage(
          estimatedTDEE: tdee,
          gender: profileGender,
          userName: userName,
          age: age,
          weight: weight,
          height: height,
          activityLevel: activityLevel,
          initialGoal: goal,
          initialCalorieTarget: calorieTarget,
        ),
      ),
    );
  }

  String? _profileGenderLabel(String value) {
    final lower = value.toLowerCase().trim();
    if (lower == 'male') return 'Male';
    if (lower == 'female') return 'Female';
    return null;
  }

  Gender _genderFromProfile(String value) {
    return value.toLowerCase().trim() == 'female' ? Gender.female : Gender.male;
  }

  double _activityMultiplier(String level) {
    switch (level) {
      case 'Light':
        return 1.375;
      case 'Moderate':
        return 1.55;
      case 'Active':
        return 1.725;
      case 'Sedentary':
      default:
        return 1.2;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Settings',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildProfileCard(context),
            const SizedBox(height: 16),
            _buildAppearanceCard(context),
            const SizedBox(height: 16),
            const _ScanImprovementCard(),
            const SizedBox(height: 16),
            if (isAdmin) ...[
              _buildAdminCard(context),
              const SizedBox(height: 16),
            ],
            _buildLogoutCard(context),
            const SizedBox(height: 24),
            const Text(
              'Esti Mobile App',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const Text(
              'Calorie tracking with food and label scanning',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFFF7E00),
                  radius: 30,
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$age years • ${weight.toStringAsFixed(1)}kg • ${height.toStringAsFixed(0)}cm',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildInfoRow('Activity Level', activityLevel),
            const SizedBox(height: 12),
            _buildInfoRow('Goal', goal),
            const SizedBox(height: 12),
            _buildInfoRow(
              'Daily Target',
              '$calorieTarget cal',
              valueColor: Colors.orange.shade800,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _openProfileEditor(context),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Edit Profile'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openGoalSetup(context),
                icon: const Icon(Icons.track_changes, color: Colors.white),
                label: const Text(
                  'Set Goal',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF7E00),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.dark_mode_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dark Theme',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'Use darker colors across the app',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch(
              value: themeController.isDark,
              onChanged: themeController.setDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF7E00).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Color(0xFFFF7E00),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Tools',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Manage Esti food data and model versions',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutCard(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _showLogoutConfirmation(context),
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text(
              'Log Out',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _logout(context);
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: valueColor),
        ),
      ],
    );
  }
}

class _ScanImprovementCard extends StatefulWidget {
  const _ScanImprovementCard();

  @override
  State<_ScanImprovementCard> createState() => _ScanImprovementCardState();
}

class _ScanImprovementCardState extends State<_ScanImprovementCard> {
  static const _prefKey = 'scan_photo_improvement_opt_in';
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var enabled = prefs.getBool(_prefKey) ?? false;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final data = doc.data();
        final remote = data?['scanPhotoImprovementOptIn'];
        if (remote is bool) {
          enabled = remote;
          await prefs.setBool(_prefKey, enabled);
        }
      } catch (_) {
        // use local setting if firestore not ready
      }
    }

    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool value) async {
    setState(() {
      _enabled = value;
      _saving = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          // permission for using ur scan photo to improve model
          'scanPhotoImprovementOptIn': value,
          'scanPhotoImprovementUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save setting: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.auto_awesome_motion_rounded,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Improve Scans',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'Allow Esti to use future scan photos for model improvement.',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (_loading || _saving)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(value: _enabled, onChanged: _setEnabled),
          ],
        ),
      ),
    );
  }
}
