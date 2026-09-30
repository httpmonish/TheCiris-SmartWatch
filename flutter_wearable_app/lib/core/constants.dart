import 'package:flutter/material.dart';

class AppConstants {
  // BLE UUIDs
  static const String serviceUuid = "0000FFE0-0000-1000-8000-00805F9B34FB";
  static const String telemetryCharUuid = "0000FFE1-0000-1000-8000-00805F9B34FB";
  static const String oledSyncCharUuid = "0000FF02-0000-1000-8000-00805F9B34FB";

  // Vitals & Sensor Thresholds
  static const double hrMinNormal = 50.0;
  static const double hrMaxNormal = 110.0;
  static const double hrCriticalHigh = 140.0;
  static const double spo2CriticalLow = 90.0;
  static const double spo2WarningLow = 94.0;
  
  static const double skinTempFever = 38.0;
  static const double skinTempCritical = 39.2;
  static const double heatIndexDanger = 41.0;
  static const double heatIndexExtremeDanger = 54.0;

  // Motion Thresholds (BMI270)
  static const double freeFallG = 0.55 * 9.80665; // ~5.39 m/s^2
  static const double impactG = 3.20 * 9.80665;   // ~31.38 m/s^2

  // Risk Weights
  static const double wFall = 0.35;
  static const double wCardiac = 0.25;
  static const double wHeat = 0.20;
  static const double wSkinDelta = 0.10;
  static const double wHypoxia = 0.10;

  // Escalation Timers
  static const int sosAutoCountdownSeconds = 15;
  static const int sosManualCountdownSeconds = 10;
}

class AppColors {
  static const Color background = Color(0xFF090D16);
  static const Color surface = Color(0xFF131C2E);
  static const Color surfaceBorder = Color(0xFF1E293B);
  
  static const Color primary = Color(0xFF38BDF8); // Cyan
  static const Color accentGreen = Color(0xFF10B981); // Emerald
  static const Color warningYellow = Color(0xFFFACC15); // Amber
  static const Color warningOrange = Color(0xFFF97316); // Orange
  static const Color dangerRed = Color(0xFFEF4444); // Red
  static const Color purple = Color(0xFFA855F7); // Purple
  
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
}
