import 'package:flutter/material.dart';

ThemeData get christmasTheme {
  final colorScheme = const ColorScheme.light().copyWith(
    primary: Colors.white,
    onPrimary: const Color(0xFFC62828), 
    secondary: Colors.white, 
    onSecondary: const Color(0xFFC62828),
    surface: const Color(0xFF1B5E20), 
    onSurface: Colors.white,
    background: const Color(0xFFC62828), 
    onBackground: Colors.white,
    error: Colors.redAccent,
    onError: Colors.white,
  );

  final base = ThemeData.from(colorScheme: colorScheme, useMaterial3: false);

  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFC62828),
    primaryColor: Colors.white,
    
    textTheme: base.textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
      decorationColor: Colors.white,
    ).copyWith(
      bodySmall: base.textTheme.bodySmall?.copyWith(color: Colors.white70),
      labelSmall: base.textTheme.labelSmall?.copyWith(color: Colors.white70),
      titleSmall: base.textTheme.titleSmall?.copyWith(color: Colors.white70),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFFC62828)),
    ),

    iconTheme: const IconThemeData(color: Colors.white),

    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF8E0000), 
      foregroundColor: Colors.white,
      iconTheme: IconThemeData(color: Colors.white),
      elevation: 0,
    ),

    cardColor: const Color(0xFF2E7D32),

    cardTheme: const CardThemeData(
      color: Color(0xFF2E7D32), 
      elevation: 4,
      shadowColor: Colors.black54,
    ),
    
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xFF8E0000), 
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 16),
    ),

    inputDecorationTheme: const InputDecorationTheme(
      labelStyle: TextStyle(color: Colors.white),
      hintStyle: TextStyle(color: Colors.white60),
      prefixIconColor: Colors.white,
      suffixIconColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white54),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white, width: 2),
      ),
      filled: true,
      fillColor: Colors.white10,
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Color(0xFF2E7D32),
      foregroundColor: Colors.white,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFFC62828), 
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Colors.white),
    ),

    listTileTheme: const ListTileThemeData(
      textColor: Colors.white,
      iconColor: Colors.white,
    ),
    dividerTheme: const DividerThemeData(color: Colors.white24),

    datePickerTheme: DatePickerThemeData(
      backgroundColor: const Color(0xFF8E0000),
      headerBackgroundColor: const Color(0xFFC62828),
      headerForegroundColor: Colors.white,
      weekdayStyle: const TextStyle(color: Colors.white70),
      dayStyle: const TextStyle(color: Colors.white),
      yearStyle: const TextStyle(color: Colors.white70),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return const Color(0xFFC62828);
          if (states.contains(WidgetState.disabled)) return Colors.white30;
          return Colors.white;
      }),
      todayBackgroundColor: WidgetStateProperty.all(const Color(0xFF2E7D32)),
      todayForegroundColor: WidgetStateProperty.all(Colors.white),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return Colors.white70;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return null;
      }),
      cancelButtonStyle: ButtonStyle(foregroundColor: WidgetStateProperty.all(Colors.white)),
      confirmButtonStyle: ButtonStyle(foregroundColor: WidgetStateProperty.all(Colors.white)),
    ),
    
    canvasColor: const Color(0xFF1B5E20),
  );
}