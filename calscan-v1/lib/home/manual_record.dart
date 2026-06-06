import 'package:flutter/material.dart';
import 'package:calscan/logic/crud_records.dart';

Future<void> showManualRecordDialog(BuildContext context) async {
  final nameController = TextEditingController();
  final calorieController = TextEditingController();
  String selectedPortion = '1 portion';
  final RecordService recordService = RecordService();

  return showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add Meal Manually'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Meal Name'),
            ),
            TextField(
              controller: calorieController,
              decoration: const InputDecoration(labelText: 'Calories'),
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
                  'protein': 0,
                  'carbs': 0,
                  'fat': 0,
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
