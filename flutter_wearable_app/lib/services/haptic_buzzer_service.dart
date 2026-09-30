import 'dart:async';

enum EmergencyEventType {
  heatStressWarning,
  cardiacAnomaly,
  confirmedFallEmergency,
  manualPanicButtonPressed,
  dismissalCountdownExpiring10s,
  escalationTriggered15s,
}

class HapticBuzzerSpec {
  final List<int> vibrationPatternMs; // [delay, vibrate, pause, vibrate...]
  final int buzzerBeepCount;
  final int buzzerFrequencyHz;
  final String description;

  const HapticBuzzerSpec({
    required this.vibrationPatternMs,
    required this.buzzerBeepCount,
    required this.buzzerFrequencyHz,
    required this.description,
  });
}

/// Concrete Hardware Haptic & Buzzer Timing Engine
class HapticBuzzerService {
  static final HapticBuzzerService _instance = HapticBuzzerService._internal();
  factory HapticBuzzerService() => _instance;
  HapticBuzzerService._internal();

  /// Exact timing matrix specified by the system design:
  static const Map<EmergencyEventType, HapticBuzzerSpec> eventSpecs = {
    // 1. Heat Stress: 2 pulses (400ms ON / 200ms OFF), 2 short beeps
    EmergencyEventType.heatStressWarning: HapticBuzzerSpec(
      vibrationPatternMs: [0, 400, 200, 400],
      buzzerBeepCount: 2,
      buzzerFrequencyHz: 1200,
      description: "2 pulses (400ms on / 200ms off) - Moderate calm alert",
    ),

    // 2. Cardiac Anomaly: 3 pulses (200ms ON / 150ms OFF), 3 sharp beeps
    EmergencyEventType.cardiacAnomaly: HapticBuzzerSpec(
      vibrationPatternMs: [0, 200, 150, 200, 150, 200],
      buzzerBeepCount: 3,
      buzzerFrequencyHz: 2400,
      description: "3 sharp pulses (200ms on / 150ms off) - Fast rhythm urgency",
    ),

    // 3. Confirmed Fall / Motion Emergency: Continuous 3000ms buzz & tone
    EmergencyEventType.confirmedFallEmergency: HapticBuzzerSpec(
      vibrationPatternMs: [0, 3000],
      buzzerBeepCount: 1,
      buzzerFrequencyHz: 3000,
      description: "Continuous 3-second buzz & alarm - Maximum urgency",
    ),

    // 4. Panic Button Pressed (Manual): 1 long 800ms pulse + 1 confirmation beep
    EmergencyEventType.manualPanicButtonPressed: HapticBuzzerSpec(
      vibrationPatternMs: [0, 800],
      buzzerBeepCount: 1,
      buzzerFrequencyHz: 1500,
      description: "1 long pulse (800ms) - Manual user acknowledgment",
    ),

    // 5. Dismissal Window Expiring at 10s: 3 pulses warning intensity
    EmergencyEventType.dismissalCountdownExpiring10s: HapticBuzzerSpec(
      vibrationPatternMs: [0, 250, 100, 250, 100, 250],
      buzzerBeepCount: 3,
      buzzerFrequencyHz: 2800,
      description: "3 escalated pulses at 10s - Prompting wearer confirmation",
    ),

    // 6. Escalation Triggered at 15s: 5 urgent pulses + automated dispatch
    EmergencyEventType.escalationTriggered15s: HapticBuzzerSpec(
      vibrationPatternMs: [0, 150, 80, 150, 80, 150, 80, 150, 80, 150],
      buzzerBeepCount: 5,
      buzzerFrequencyHz: 3500,
      description: "5 rapid pulses at 15s - Automated dispatch active",
    ),
  };

  /// Dispatches the pattern to hardware (over BLE characteristic) and mobile vibrator
  void triggerPattern(EmergencyEventType event) {
    final spec = eventSpecs[event]!;
    // In production: writes [0xFE, event.index, ...pattern] to Watch Haptic BLE characteristic
    // Also invokes SystemSound or Vibration.vibrate(pattern: spec.vibrationPatternMs)
  }
}
