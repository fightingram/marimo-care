import 'package:flutter/material.dart';

class PresetBackground {
  final String name;
  final Gradient gradient;
  const PresetBackground(this.name, this.gradient);
}

// Water-like default background first
const List<PresetBackground> presetBackgrounds = [
  PresetBackground(
    '水',
    LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFB3E5FC), Color(0xFF81D4FA), Color(0xFF4FC3F7), Color(0xFF1E88E5)],
      stops: [0.0, 0.35, 0.7, 1.0],
    ),
  ),
  PresetBackground('春', LinearGradient(colors: [Color(0xFFFA709A), Color(0xFFFEE140)])),
  PresetBackground('夏', LinearGradient(colors: [Color(0xFF00C6FF), Color(0xFF0072FF)])),
  PresetBackground('秋', LinearGradient(colors: [Color(0xFFF7971E), Color(0xFFFFD200)])),
  PresetBackground('冬', LinearGradient(colors: [Color(0xFF83a4d4), Color(0xFFb6fbff)])),
  PresetBackground('和紙', LinearGradient(colors: [Color(0xFFB993D6), Color(0xFF8CA6DB)])),
  PresetBackground('宇宙', LinearGradient(colors: [Color(0xFF0F2027), Color(0xFF2C5364)])),
  PresetBackground('深海', LinearGradient(colors: [Color(0xFF000428), Color(0xFF004e92)])),
  PresetBackground('木漏れ日', LinearGradient(colors: [Color(0xFF56ab2f), Color(0xFFA8E063)])),
  PresetBackground('夜景', LinearGradient(colors: [Color(0xFF434343), Color(0xFF000000)])),
  PresetBackground('苔庭', LinearGradient(colors: [Color(0xFF11998e), Color(0xFF38ef7d)])),
  PresetBackground('雪', LinearGradient(colors: [Color(0xFFe6dada), Color(0xFF274046)])),
];

