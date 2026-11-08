import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/app_themes.dart'; // Importação das definições

class ThemeService extends ChangeNotifier {
  String _currentTheme = 'light';
  String _forcedTheme = 'none'; // Configuração global do Firestore

  String get currentTheme =>
      _forcedTheme != 'none' ? _forcedTheme : _currentTheme;
  bool get isThemeLocked => _forcedTheme != 'none';

  ThemeService() {
    _loadSettings();
    _listenToGlobalSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _currentTheme = prefs.getString('user_theme') ?? 'light';
    notifyListeners();
  }

  void _listenToGlobalSettings() {
    FirebaseFirestore.instance
        .collection('settings')
        .doc('app_config')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        _forcedTheme = data?['forced_theme'] ?? 'none';
        notifyListeners();
      }
    });
  }

  Future<void> setTheme(String theme) async {
    if (isThemeLocked) return; // Não permite mudar se estiver travado
    _currentTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_theme', theme);
    notifyListeners();
  }

  ThemeData getThemeData() {
    String themeToUse = currentTheme;

    switch (themeToUse) {
      case 'dark':
        return AppThemes.dark;
      case 'pink':
        return AppThemes.pink;
      case 'blue':
        return AppThemes.blue;
      case 'brazil':
        return AppThemes.brazil;
      case 'christmas':
        return AppThemes.christmas;
      case 'light':
        return AppThemes.light;
      case 'purpleOrange':
        return AppThemes.purpleOrange;
      default:
        return AppThemes.light;
    }
  }
}
