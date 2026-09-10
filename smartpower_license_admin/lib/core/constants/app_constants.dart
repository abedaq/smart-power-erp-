import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'SmartPower Admin';
  static const String appTitle = 'لوحة إدارة وتراخيص SmartPower';
  static const String appVersion = '1.0.0';

  // Supabase Configuration
  static const String supabaseUrl = 'https://pkuoytiickgbtfeffmxq.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBrdW95dGlpY2tnYnRmZWZmbXhxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0NDk0MjAsImV4cCI6MjEwNDAyNTQyMH0.9aGjAHdibP2uKiiTQ8XuGsYmwsZeWsA3hVQ9gD4xq7Q';

  // Default Passcode
  static const String defaultPasscode = '2026';

  // Palette
  static const Color primary = Color(0xFF1E3A8A); // Dark Blue
  static const Color primaryLight = Color(0xFF3B82F6); // Blue Accent
  static const Color secondary = Color(0xFF0F172A); // Slate 900
  static const Color background = Color(0xFFF8FAFC); // Slate 50
  static const Color surface = Color(0xFFFFFFFF);
  static const Color success = Color(0xFF059669); // Emerald 600
  static const Color warning = Color(0xFFD97706); // Amber 600
  static const Color danger = Color(0xFFDC2626); // Red 600
  static const Color textMain = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
}
