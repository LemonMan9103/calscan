import 'package:flutter/material.dart';
import 'package:calscan/home/main_wrapper.dart';
import 'package:calscan/logic/calorie_calculation.dart';
import 'package:calscan/logic/firestore_service.dart';

class GoalSetupPage extends StatefulWidget {
  final double estimatedTDEE;
  final Gender gender;
  final String userName;
  final int age;
  final double weight;
  final double height;
  final String activityLevel;

  const GoalSetupPage({
    super.key,
    required this.estimatedTDEE,
    required this.gender,
    required this.userName,
    required this.age,
    required this.weight,
    required this.height,
    required this.activityLevel,
  });

  @override
  State<GoalSetupPage> createState() => _GoalSetupPageState();
}

class _GoalSetupPageState extends State<GoalSetupPage> {
  String _selectedGoal = 'Maintain Weight';
  final TextEditingController _customController = TextEditingController(
    text: '',
  );
  bool _isLoading = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  Future<void> _completeSetup(int deficit, int surplus) async {
    int finalTarget;
    if (_selectedGoal == 'Custom Goal') {
      finalTarget = int.tryParse(_customController.text) ?? 2000;
    } else if (_selectedGoal == 'Lose Weight') {
      finalTarget = (widget.estimatedTDEE - deficit).toInt();
    } else if (_selectedGoal == 'Gain Weight') {
      finalTarget = (widget.estimatedTDEE + surplus).toInt();
    } else {
      finalTarget = widget.estimatedTDEE.toInt();
    }

    setState(() => _isLoading = true);

    try {
      // Save to Firestore
      await FirestoreService().saveUserProfile(
        name: widget.userName,
        weight: widget.weight,
        height: widget.height,
        age: widget.age,
        activityLevel: widget.activityLevel,
        goal: _selectedGoal,
        calorieTarget: finalTarget,
      );

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => MainWrapper(
              userName: widget.userName,
              calorieTarget: finalTarget,
              age: widget.age,
              weight: widget.weight,
              height: widget.height,
              activityLevel: widget.activityLevel,
              goal: _selectedGoal,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    int deficitValue = CalorieCalculator.calculateSafeDeficit(
      widget.estimatedTDEE,
      widget.gender,
    );

    int surplusValue = 300;
    int customLimit = (widget.gender == Gender.male) ? 1500 : 1200;

    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Goal Setup',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('Step 2 of 2', style: TextStyle(color: Colors.grey)),
                    Text('100%', style: TextStyle(color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: 1.0,
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.redAccent,
                    ),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBF3FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: Color(0xFF1E3A8A),
                            fontSize: 16,
                          ),
                          children: [
                            const TextSpan(
                              text: 'Your estimated daily calorie needs: ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            TextSpan(
                              text:
                                  '${widget.estimatedTDEE.toStringAsFixed(0)} calories',
                              style: const TextStyle(color: Color(0xFF1E1B4B)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Based on your age, weight, height, and activity level',
                        style: TextStyle(color: Color(0xFF3B82F6), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildGoalCard(
                  title: 'Lose Weight',
                  subtitle: '$deficitValue cal deficit per day',
                  calories:
                      '${(widget.estimatedTDEE - deficitValue).toStringAsFixed(0)} cal/day',
                  icon: Icons.trending_down,
                  iconBgColor: Colors.blue,
                ),
                const SizedBox(height: 12),
                _buildGoalCard(
                  title: 'Maintain Weight',
                  subtitle: 'Balanced calorie intake',
                  calories: '${widget.estimatedTDEE.toStringAsFixed(0)} cal/day',
                  icon: Icons.remove,
                  iconBgColor: Colors.green,
                ),
                const SizedBox(height: 12),
                _buildGoalCard(
                  title: 'Gain Weight',
                  subtitle: '$surplusValue cal surplus per day',
                  calories:
                      '${(widget.estimatedTDEE + surplusValue).toStringAsFixed(0)} cal/day',
                  icon: Icons.trending_up,
                  iconBgColor: const Color(0xFFA855F7),
                ),
                const SizedBox(height: 12),
                _buildGoalCard(
                  title: 'Custom Goal',
                  subtitle: 'Set your own target',
                  icon: Icons.track_changes,
                  iconBgColor: Colors.deepOrange,
                  isCustom: true,
                  warningLimit: customLimit,
                ),
                const SizedBox(height: 24),
                _buildCompleteButton(deficitValue, surplusValue),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'You can change your goal anytime in settings',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildGoalCard({
    required String title,
    required String subtitle,
    String? calories,
    required IconData icon,
    required Color iconBgColor,
    bool isCustom = false,
    int? warningLimit,
  }) {
    bool isSelected = _selectedGoal == title;
    return GestureDetector(
      onTap: () => setState(() => _selectedGoal = title),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.grey.shade200,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      if (calories != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          calories,
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: Colors.orange,
                    size: 28,
                  ),
              ],
            ),
            if (isCustom && isSelected)
              Padding(
                padding: const EdgeInsets.only(top: 16, left: 60),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _customController,
                      keyboardType: TextInputType.number,
                      onChanged: (value) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Enter daily target',
                        suffixText: 'kcal',
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    if (warningLimit != null &&
                        (int.tryParse(_customController.text) ?? 0) <
                            warningLimit &&
                        _customController.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, left: 4.0),
                        child: Text(
                          'Warning: It is not recommended to intake below $warningLimit calories per day',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompleteButton(int deficit, int surplus) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
        ),
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : () => _completeSetup(deficit, surplus),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'Complete Setup',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.check, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

