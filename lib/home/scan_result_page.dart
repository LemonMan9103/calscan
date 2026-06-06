import 'dart:io';
import 'package:flutter/material.dart';
import 'package:calscan/logic/firestore_service.dart';
import 'package:calscan/logic/food_lookup_service.dart';

class ScanResultPage extends StatefulWidget {
  /// The photo that was captured.
  final File imageFile;

  /// Result map returned by RecognitionService:
  ///   { 'labelKey': String, 'confidence': double }
  /// Null means nothing was detected above the confidence threshold.
  final Map<String, dynamic>? result;

  const ScanResultPage({
    super.key,
    required this.imageFile,
    required this.result,
  });

  @override
  State<ScanResultPage> createState() => _ScanResultPageState();
}

class _ScanResultPageState extends State<ScanResultPage>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final FoodLookupService _lookup = FoodLookupService();

  bool _isSaving = false;
  bool _saved = false;

  // Portion selection — default to Medium
  PortionSize _portion = PortionSize.medium;

  late final AnimationController _animController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  // Derived from result
  String? _labelKey;
  double _confidence = 0;

  @override
  void initState() {
    super.initState();
    if (widget.result != null) {
      _labelKey = widget.result!['labelKey'] as String?;
      _confidence = (widget.result!['confidence'] as num?)?.toDouble() ?? 0;
    }

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  double get _currentCalories =>
      _labelKey != null ? _lookup.getCalories(_labelKey!, _portion) : 0;

  String get _displayName =>
      _labelKey != null ? _lookup.getDisplayName(_labelKey!) : '';

  String get _description =>
      _labelKey != null ? _lookup.getDescription(_labelKey!) : '';

  Future<void> _saveAndLog() async {
    if (_isSaving || _saved || _labelKey == null) return;
    setState(() => _isSaving = true);

    await _firestoreService.saveMeal(
      mealName: _displayName,
      calories: _currentCalories,
      protein: 0,
      carbs: 0,
      fat: 0,
      portion: _portion.label,
    );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _saved = true;
    });

    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      Navigator.of(context)
        ..pop()
        ..pop();
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasResult = widget.result != null && _labelKey != null;

    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F5),
      body: Stack(
        children: [
          // ── Captured image (top half) ──────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.48,
            child: Hero(
              tag: 'captured_image',
              child: Image.file(
                widget.imageFile,
                fit: BoxFit.cover,
              ),
            ),
          ),

          // Gradient fade into card
          Positioned(
            top: MediaQuery.of(context).size.height * 0.30,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.18,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFFFDF8F5).withValues(alpha: 0.95),
                  ],
                ),
              ),
            ),
          ),

          // ── Back button ────────────────────────────────────────────────
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: _CircleIconButton(
                  icon: Icons.arrow_back,
                  onTap: () => Navigator.pop(context),
                ),
              ),
            ),
          ),

          // ── Result card (bottom) ───────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideUp,
                child: hasResult
                    ? _buildDetectedCard(context)
                    : _buildNotDetectedCard(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Detected card ──────────────────────────────────────────────────────────

  Widget _buildDetectedCard(BuildContext context) {
    final int pct = (_confidence * 100).round();
    final Color confColor = _confidence > 0.7
        ? const Color(0xFF28A745)
        : _confidence > 0.45
            ? const Color(0xFFFF7E00)
            : const Color(0xFFDC3545);

    return Container(
      height: MediaQuery.of(context).size.height * 0.58,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      decoration: const BoxDecoration(
        color: Color(0xFFFDF8F5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: AI chip + confidence badge ─────────────────────
          Row(
            children: [
              _buildChip(
                icon: Icons.auto_awesome,
                label: 'AI Detected',
                gradient: true,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: confColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: confColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified, color: confColor, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '$pct% match',
                      style: TextStyle(
                        color: confColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Food name + description ──────────────────────────────────
          Text(
            _displayName,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),

          const SizedBox(height: 16),

          // ── Portion selector ─────────────────────────────────────────
          _buildPortionSelector(),

          const SizedBox(height: 16),

          // ── Calorie card ─────────────────────────────────────────────
          _buildCalorieCard(),

          const SizedBox(height: 14),

          // ── Confidence bar ───────────────────────────────────────────
          _buildConfidenceBar(confColor),

          const Spacer(),

          // ── Action buttons ───────────────────────────────────────────
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildPortionSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Portion Size',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: PortionSize.values.map((p) {
            final bool selected = _portion == p;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _portion = p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? const LinearGradient(
                            colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
                          )
                        : null,
                    color: selected ? null : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? Colors.transparent
                          : Colors.grey.shade200,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: const Color(0xFFFF7E00).withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    children: [
                      Text(
                        p.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: selected ? Colors.white : Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '×${_lookup.portionMultipliers[p.key]?.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: selected
                              ? Colors.white70
                              : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCalorieCard() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: ScaleTransition(scale: anim, child: child)),
      child: Container(
        key: ValueKey(_portion),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF7E00).withValues(alpha: 0.3),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Estimated Calories',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_currentCalories.toInt()} kcal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              '${_portion.label} (×${_lookup.portionMultipliers[_portion.key]?.toStringAsFixed(1)})',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfidenceBar(Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Detection Confidence',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
            ),
            Text(
              '${(_confidence * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _confidence),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 7,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retake'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF7E00),
              side: const BorderSide(color: Color(0xFFFF7E00)),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _saved ? _buildSavedButton() : _buildSaveButton(),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton.icon(
      key: const ValueKey('save'),
      onPressed: _isSaving ? null : _saveAndLog,
      icon: _isSaving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.add_circle_outline_rounded, color: Colors.white),
      label: Text(
        _isSaving ? 'Saving...' : 'Save & Log',
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFF7E00),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    );
  }

  Widget _buildSavedButton() {
    return ElevatedButton.icon(
      key: const ValueKey('saved'),
      onPressed: null,
      icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
      label: const Text(
        'Logged!',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF28A745),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    );
  }

  // ── Not detected card ──────────────────────────────────────────────────────

  Widget _buildNotDetectedCard(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.54,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
      decoration: const BoxDecoration(
        color: Color(0xFFFDF8F5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.no_food_outlined,
                size: 48, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Food Detected',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'The model could not identify any food with enough confidence.\nMake sure the food is clearly visible and well-lit.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: Colors.grey.shade500, height: 1.5),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.camera_alt_rounded, color: Colors.white),
              label: const Text(
                'Try Again',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7E00),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _buildChip({
    required IconData icon,
    required String label,
    bool gradient = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: gradient
            ? const LinearGradient(
                colors: [Color(0xFFFF7E00), Color(0xFFFF4B2B)])
            : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ─── Helper widget ─────────────────────────────────────────────────────────────

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
