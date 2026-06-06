import 'package:flutter/material.dart';
import 'package:calscan/logic/crud_records.dart';

Future<void> showManualRecordDialog(BuildContext context) async {
  final nameController = TextEditingController();
  final calorieController = TextEditingController();
  final proteinController = TextEditingController();
  final carbsController = TextEditingController();
  final fatController = TextEditingController();
  String selectedPortion = '1 portion';
  final RecordService recordService = RecordService();

  return showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add Meal Manually'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Meal Name'),
              ),
              TextField(
                controller: calorieController,
                decoration: const InputDecoration(labelText: 'Calories (kcal)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: proteinController,
                decoration: const InputDecoration(labelText: 'Protein (g)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: carbsController,
                decoration: const InputDecoration(labelText: 'Carbs (g)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: fatController,
                decoration: const InputDecoration(labelText: 'Fat (g)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                value: selectedPortion,
                isExpanded: true,
                items: ['1 portion', '1 cup', '1 plate', '1 pcs', '1 part'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (val) => setDialogState(() => selectedPortion = val!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty && calorieController.text.isNotEmpty) {
                await recordService.addMeal({
                  'mealName': nameController.text,
                  'calories': double.tryParse(calorieController.text) ?? 0,
                  'protein': double.tryParse(proteinController.text) ?? 0,
                  'carbs': double.tryParse(carbsController.text) ?? 0,
                  'fat': double.tryParse(fatController.text) ?? 0,
                  'portion': selectedPortion,
                });
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
