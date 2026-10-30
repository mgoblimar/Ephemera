import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tests turn this off so fonts aren't fetched over the network.
bool useGoogleFonts = true;

/// A handwriting font from Google Fonts (fetched once, then cached on device).
TextStyle handwriting(String font, {required double fontSize, Color? color}) {
  if (!useGoogleFonts) {
    return TextStyle(fontFamily: font, fontSize: fontSize, color: color);
  }
  return GoogleFonts.getFont(font, fontSize: fontSize, color: color);
}
