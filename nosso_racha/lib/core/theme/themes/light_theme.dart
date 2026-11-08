import 'package:flutter/material.dart';

ThemeData get lightTheme => ThemeData(
      useMaterial3: false,
      primarySwatch: Colors.green,
      scaffoldBackgroundColor: Colors.grey[100],
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 2,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
        titleTextStyle: TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold),
        contentTextStyle: TextStyle(color: Colors.black87, fontSize: 16),
      ),
    );