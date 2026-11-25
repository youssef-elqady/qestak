import 'package:flutter/material.dart';

/// Status colors used consistently across the app.
class QestakColors {
  static const navy = Color(0xFF0F1B2D);
  static const gold = Color(0xFFC9A24B);
  static const paid = Color(0xFF2E9E5B);
  static const upcoming = Color(0xFFE08A1E);
  static const overdue = Color(0xFFD64545);
}

class QestakTheme {
  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: QestakColors.navy,
          secondary: QestakColors.gold,
          brightness: Brightness.light,
        ),
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: QestakColors.navy,
          secondary: QestakColors.gold,
          brightness: Brightness.dark,
        ),
      );
}
