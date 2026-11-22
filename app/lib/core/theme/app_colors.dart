import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF101D35);
  static const navyLight = Color(0xFF1B2B4D);
  static const teal = Color(0xFF16B8A6);
  static const amber = Color(0xFFF5B94C);
  static const softWhite = Color(0xFFF5F7FB);
  static const lavender = Color(0xFF7966D9);
  static const coral = Color(0xFFF07878);
  static const success = Color(0xFF1FA971);
  static const warning = Color(0xFFE0A030);
  static const danger = Color(0xFFD9534F);

  static const heroGradient = [navy, Color(0xFF233E6E), lavender];
  static const tealGradient = [teal, Color(0xFF0E8C9E)];
  static const amberGradient = [amber, coral];
  static const lavenderGradient = [lavender, Color(0xFF4F7BE0)];

  static Color fromHex(String? hex, {Color fallback = teal}) {
    if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return fallback;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }
}

/// Opacity helper that works on every supported Flutter version.
Color fade(Color c, double opacity) => c.withAlpha((opacity.clamp(0, 1) * 255).round());
