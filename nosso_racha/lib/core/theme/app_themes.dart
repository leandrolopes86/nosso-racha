import 'package:flutter/material.dart';

// Importa todos os temas individuais separados
import 'themes/light_theme.dart';
import 'themes/dark_theme.dart';
import 'themes/purple_orange_theme.dart';
import 'themes/christmas_theme.dart';
import 'themes/pink_theme.dart';
import 'themes/blue_theme.dart';
import 'themes/brazil_theme.dart';

class AppThemes {
  // Mantemos a mesma estrutura de getters estáticos
  // para que o resto do aplicativo (main.dart, ThemeService) continue funcionando sem edições!

  static ThemeData get light => lightTheme;
  
  static ThemeData get dark => darkTheme;
  
  static ThemeData get purpleOrange => purpleOrangeTheme;
  
  static ThemeData get christmas => christmasTheme;

  static ThemeData get pink => pinkTheme;
  
  static ThemeData get blue => blueTheme;
  
  static ThemeData get brazil => brazilTheme;
}