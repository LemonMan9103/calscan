import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:calscan/profile/goal_setup.dart';
import 'package:calscan/logic/calorie_calculation.dart';
import 'package:calscan/home/main_wrapper.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  String? _selectedGender;
  String? _selectedActivityLevel;

  final TextEditingController _nameController = TextEditingController(text: '');
  final TextEditingController _ageController = TextEditingController(text: '');
  final TextEditingController _weightController = TextEditingController(
    text: '',
  );
  final TextEditingController _heightController = TextEditingController(
    text: '',
  );

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  double _getActivityMultiplier(String level) {
    switch (level) {
      case 'Sedentary':
        return 1.2;
      case 'Light':
        return 1.375;
      case 'Moderate':
        return 1.55;
      case 'Active':
        return 1.725;
      default:
        return 1.2;
    }
  }

  bool _isFormValid() {
    return _nameController.text.isNotEmpty &&
        _ageController.text.isNotEmpty &&
        _weightController.text.isNotEmpty &&
        _heightController.text.isNotEmpty &&
        _selectedGender != null &&
        _selectedActivityLevel != null;
  }

  void _onContinue() {
    if (!_isFormValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields before continuing'),
        ),
      );
      return;
    }

    final double weight = double.tryParse(_weightController.text) ?? 65.0;
    final double height = double.tryParse(_heightController.text) ?? 170.0;
    final int age = int.tryParse(_ageController.text) ?? 25;
    final Gender gender = _selectedGender == 'Male'
        ? Gender.male
        : Gender.female;

    final double bmr = CalorieCalculator.calculateBMR(
      weightKg: weight,
      heightCm: height,
      age: age,
      gender: gender,
    );

    final double multiplier = _getActivityMultiplier(_selectedActivityLevel!);
    final double tdee = CalorieCalculator.calculateTDEE(bmr, multiplier);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GoalSetupPage(
          estimatedTDEE: tdee,
          gender: gender,
          userName: _nameController.text,
          age: age,
          weight: weight,
          height: height,
          activityLevel: _selectedActivityLevel!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile Setup',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => const MainWrapper(
                    userName: 'Guest',
                    calorieTarget: 2000,
                    age: 25,
                    weight: 65.0,
                    height: 170.0,
                    activityLevel: 'Sedentary',
                    goal: 'custom',
                  ),
                ),
                (route) => false,
              );
            },
            child: const Text(
              'Skip',
              style: TextStyle(
                color: Color(0xFFFF7E00),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('Step 1 of 2', style: TextStyle(color: Colors.grey)),
                Text('50%', style: TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: 0.5,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFFF7E00),
                ),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFFFF7E00),
                          radius: 24,
                          child: const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Personal Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Tell us about yourself',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildLabel('Name'),
                    _buildTextField(
                      controller: _nameController,
                      hintText: 'e.g. Guest',
                    ),
                    const SizedBox(height: 20),
                    _buildLabel('Gender'),
                    Row(
                      children: [
                        Expanded(
                          child: _buildGenderCard(
                            'Male',
                            Icons.male,
                            _selectedGender == 'Male',
                            const Color(0xFF4D82F5),
                            Color(0xFF4D82F5).withValues(alpha: 0.1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildGenderCard(
                            'Female',
                            Icons.female,
                            _selectedGender == 'Female',
                            const Color(0xFFEC4899),
                            Color(0xFFEC4899).withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Age'),
                              _buildNumberField(
                                controller: _ageController,
                                hintText: '25',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Weight (kg)'),
                              _buildNumberField(
                                controller: _weightController,
                                hintText: '65',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Height (cm)'),
                              _buildNumberField(
                                controller: _heightController,
                                hintText: '170',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildLabel('Activity Level'),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 2.0,
                      children: [
                        _buildActivityCard(
                          'Sedentary',
                          'Little to no exercise',
                        ),
                        _buildActivityCard('Light', '1–3 days/week'),
                        _buildActivityCard('Moderate', '3–5 days/week'),
                        _buildActivityCard('Active', '6–7 days/week'),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _buildContinueButton(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Your data is stored locally and used to calculate personalized calorie intake',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
  }) {
    return TextField(
      controller: controller,
      onChanged: (value) => setState(() {}),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey.shade400),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String hintText,
  }) {
    return TextField(
      controller: controller,
      onChanged: (value) => setState(() {}),
      keyboardType: TextInputType.number,
      inputFormatters: [
        LengthLimitingTextInputFormatter(4),
        FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey.shade400),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildGenderCard(
    String label,
    IconData icon,
    bool isSelected,
    Color primaryColor,
    Color bgColor,
  ) {
    return GestureDetector(
      onTap: () => setState(() => _selectedGender = label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? bgColor
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primaryColor : Theme.of(context).dividerColor,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected
                  ? primaryColor
                  : Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? primaryColor
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard(String title, String subtitle) {
    bool isSelected = _selectedActivityLevel == title;
    return GestureDetector(
      onTap: () => setState(() => _selectedActivityLevel = title),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? Color(0xFFFF7E00).withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF7E00)
                : Theme.of(context).dividerColor,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 10),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    bool isValid = _isFormValid();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: isValid
            ? const LinearGradient(
                colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
              )
            : LinearGradient(
                colors: [Colors.grey.shade400, Colors.grey.shade400],
              ),
      ),
      child: ElevatedButton(
        onPressed: isValid ? _onContinue : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'Continue to Goal Setup',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
