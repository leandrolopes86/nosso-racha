import 'package:flutter/material.dart';

ThemeData get purpleOrangeTheme => ThemeData(
      useMaterial3: false,
      primarySwatch: Colors.purple,
      scaffoldBackgroundColor: const Color(0xFFF3E5F5), // Roxo bem claro
      primaryColor: Colors.purple,
      
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      colorScheme: const ColorScheme.light(
        primary: Colors.purple,
        onPrimary: Colors.white,
        secondary: Colors.deepOrange, // Laranja como cor secundária
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: Colors.purple, // Texto principal Roxo
        background: Color(0xFFF3E5F5),
        onBackground: Colors.black87,
      ),
      
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.purpleAccent,
      ),

      iconTheme: const IconThemeData(color: Colors.deepOrange), // Ícones Laranja

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.deepOrange,
          side: const BorderSide(color: Colors.deepOrange),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.purple),
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        prefixIconColor: Colors.purple,
        suffixIconColor: Colors.deepOrange,
        labelStyle: const TextStyle(color: Colors.purple),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.deepOrange, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.purple.withOpacity(0.5)),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: Colors.deepOrange,
        textColor: Colors.purple,
      ),
    );