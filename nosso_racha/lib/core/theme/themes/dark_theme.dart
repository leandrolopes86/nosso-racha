import 'package:flutter/material.dart';

ThemeData get darkTheme => ThemeData.dark().copyWith(
      primaryColor: Colors.grey[900],
      scaffoldBackgroundColor: const Color(0xFF121212),
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        secondary: Colors.tealAccent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: Color(0xFF303030), 
        elevation: 2,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF303030),
        titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        contentTextStyle: TextStyle(color: Colors.white70, fontSize: 16),
      ),
    );