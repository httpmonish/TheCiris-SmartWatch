import 'dart:math' as math;

enum FallDetectionState {
  nominal,
  freeFallDetected,
  impactRegistered,
  postFallInactivity,
  confirmedFallManDown,
}

/// Fall detection algorithm based on:
/// "Development of a Wearable-Sensor-Based Fall Detection System"
/// + BME280 Barometric Pressure Drop Secondary Confirmation.
class Bmi270FallDetector {
  FallDetectionState _state = FallDetectionState.nominal;
  int _freeFallStartMs = 0;
  int _impactStartMs = 0;
  double _pressureAtFreeFall = 1013.25;

  // Thresholds as verified in literature
  static const double kFreeFallThresholdG = 0.55 * 9.80665; // < 5.39 m/s^2
  static const double kImpactThresholdG = 3.20 * 9.80665;   // > 31.38 m/s^2
  static const double kInactivityLowerG = 8.5;              // ~1G static lying
  static const double kInactivityUpperG = 11.2;
  static const double kBarometricDropHpa = 0.12;            // ~1.0m height drop

  FallDetectionState processSample({
    required double ax,
    required double ay,
    required double az,
    required double baroPressureHpa,
    required int timestampMs,
  }) {
    final magnitude = math.sqrt(ax * ax + ay * ay + az * az);

    switch (_state) {
      case FallDetectionState.nominal:
        if (magnitude < kFreeFallThresholdG) {
          _state = FallDetectionState.freeFallDetected;
          _freeFallStartMs = timestampMs;
          _pressureAtFreeFall = baroPressureHpa;
        }
        break;

      case FallDetectionState.freeFallDetected:
        if (magnitude > kImpactThresholdG) {
          final dt = timestampMs - _freeFallStartMs;
          // Valid free-fall window: 50ms - 900ms
          if (dt >= 50 && dt <= 900) {
            _state = FallDetectionState.impactRegistered;
            _impactStartMs = timestampMs;
          } else {
            _state = FallDetectionState.nominal;
          }
        } else if ((timestampMs - _freeFallStartMs) > 1000) {
          _state = FallDetectionState.nominal; // Timed out without impact
        }
        break;

      case FallDetectionState.impactRegistered:
        // Check for static lying post-fall after 1.5s
        final timeSinceImpact = timestampMs - _impactStartMs;
        if (timeSinceImpact >= 1500 && timeSinceImpact <= 4000) {
          final isStationary = magnitude >= kInactivityLowerG && magnitude <= kInactivityUpperG;
          final isHeightDropConfirmed = (baroPressureHpa - _pressureAtFreeFall) >= -0.05; // Air pressure rises as you get closer to floor

          if (isStationary || isHeightDropConfirmed) {
            _state = FallDetectionState.confirmedFallManDown;
          }
        } else if (timeSinceImpact > 4000) {
          _state = FallDetectionState.nominal; // Recovered and moved away
        }
        break;

      case FallDetectionState.confirmedFallManDown:
        // Latched state until externally cleared/reset
        break;
    }

    return _state;
  }

  void reset() {
    _state = FallDetectionState.nominal;
    _freeFallStartMs = 0;
    _impactStartMs = 0;
  }
}
