import 'dart:math' as math;
import '../core/constants.dart';

enum MotionPhase {
  nominal,
  freeFall,
  impactRegistered,
  postFallInactivity,
  confirmedFall,
}

class MotionService {
  MotionPhase _phase = MotionPhase.nominal;
  int _freeFallStartMs = 0;
  int _impactStartMs = 0;
  double _lastPressureHpa = 1013.25;

  MotionPhase processMotionFrame({
    required double ax,
    required double ay,
    required double az,
    required double pressureHpa,
    required int timestampMs,
  }) {
    final magnitude = math.sqrt(ax * ax + ay * ay + az * az);
    final magG = magnitude / 9.80665;

    switch (_phase) {
      case MotionPhase.nominal:
        if (magnitude < AppConstants.freeFallG) {
          _phase = MotionPhase.freeFall;
          _freeFallStartMs = timestampMs;
          _lastPressureHpa = pressureHpa;
        }
        break;

      case MotionPhase.freeFall:
        if (magnitude > AppConstants.impactG) {
          final dt = timestampMs - _freeFallStartMs;
          if (dt >= 50 && dt <= 900) {
            _phase = MotionPhase.impactRegistered;
            _impactStartMs = timestampMs;
          } else {
            _phase = MotionPhase.nominal;
          }
        } else if ((timestampMs - _freeFallStartMs) > 1000) {
          _phase = MotionPhase.nominal;
        }
        break;

      case MotionPhase.impactRegistered:
        final dtSinceImpact = timestampMs - _impactStartMs;
        // After impact spike settles (> 250ms):
        if (dtSinceImpact > 250) {
          // False Positive Filter: If user continues moving (g-force deviates from static 1G by > 0.25G), reset
          if ((magG - 1.0).abs() > 0.25) {
            _phase = MotionPhase.nominal;
          } else if (dtSinceImpact >= 1500 && dtSinceImpact <= 4000) {
            // Sustained immobility (static 1G for >= 1.5s) confirms fall
            _phase = MotionPhase.confirmedFall;
          } else if (dtSinceImpact > 4000) {
            _phase = MotionPhase.nominal;
          }
        }
        break;

      case MotionPhase.confirmedFall:
        // Latched state until manually reset
        break;
      case MotionPhase.postFallInactivity:
        break;
    }

    return _phase;
  }

  void reset() {
    _phase = MotionPhase.nominal;
    _freeFallStartMs = 0;
    _impactStartMs = 0;
  }
}
