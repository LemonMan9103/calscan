import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static const _preferenceKey = 'dark_theme_enabled';
  static late ThemeController instance;

  ThemeController._(this._isDark);

  bool _isDark;
  bool get isDark => _isDark;
  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  static Future<ThemeController> load() async {
    final preferences = await SharedPreferences.getInstance();
    instance = ThemeController._(preferences.getBool(_preferenceKey) ?? false);
    return instance;
  }

  Future<void> setDark(bool value) async {
    if (_isDark == value) return;
    _isDark = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_preferenceKey, value);
  }
}
