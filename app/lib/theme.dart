import 'package:flutter/material.dart';

/// Paper-and-ink palette. Handwriting fonts arrive with the canvas editor (Day 3).
abstract final class Palette {
  static const paper = Color(0xFFF4ECDD);
  static const paperDeep = Color(0xFFE8DCC4);
  static const ink = Color(0xFF2F2A26);
  static const inkSoft = Color(0xFF6B5E52);
  static const terracotta = Color(0xFFB5603F);
  static const moss = Color(0xFF6F7F5A);

  /// Tints for mask overlays on the review screen, cycled per mask.
  static const maskTints = [
    Color(0xFFE07A5F),
    Color(0xFF3D8DAE),
    Color(0xFF81B29A),
    Color(0xFFF2CC8F),
    Color(0xFF9B6BB0),
    Color(0xFFD1495B),
  ];
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.terracotta,
    surface: Palette.paper,
    onSurface: Palette.ink,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.paper,
      foregroundColor: Palette.ink,
      elevation: 0,
      centerTitle: false,
    ),
    useMaterial3: true,
  );
}
