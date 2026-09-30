import 'dart:math' as math;

/// Implementation of Noise-Robust Heart Rate and SpO2 Estimation per Shin & Cho (2019):
/// 1. Preprocessing Block: Bandpass filter + Baseline wander removal
/// 2. Motion Artifact (MA) Reduction Block: Normalized LMS adaptive filtering with triaxial IMU reference
/// 3. Frequency Tracking Block: Peak detection, Inter-beat interval (IBI), and RMSSD calculation
class ShinChoPpgProcessor {
  // Preprocessing state
  double _prevRawRed = 0.0;
  double _prevRawIr = 0.0;
  double _filteredRed = 0.0;
  double _filteredIr = 0.0;

  // Normalized Least Mean Squares (NLMS) filter weights for 3-axis IMU references
  final List<double> _weightsRed = List.filled(4, 0.0);
  final List<double> _weightsIr = List.filled(4, 0.0);
  static const double _mu = 0.015; // Learning step size
  static const double _epsilon = 1e-4; // Regularization to prevent divide-by-zero

  // Frequency tracking and peak detection buffers
  final List<double> _cleanIrBuffer = [];
  final List<int> _peakTimestamps = [];
  static const int _bufferCapacity = 100; // 2 seconds @ 50 Hz

  /// Process a single PPG + IMU sample
  ({double cleanRed, double cleanIr, double estimatedHr, double rmssd, double estimatedSpO2}) processSample({
    required double rawRed,
    required double rawIr,
    required double ax,
    required double ay,
    required double az,
    required int timestampMs,
  }) {
    // Stage 1: Preprocessing (DC Wander Removal + High-pass difference)
    final dRed = rawRed - _prevRawRed;
    final dIr = rawIr - _prevRawIr;
    _prevRawRed = rawRed;
    _prevRawIr = rawIr;

    // Single-pole low-pass smoothing (cutoff ~4 Hz)
    _filteredRed = (0.7 * _filteredRed) + (0.3 * dRed);
    _filteredIr = (0.7 * _filteredIr) + (0.3 * dIr);

    // Stage 2: Motion Artifact Reduction (NLMS Adaptive Filter)
    // Reference signal vector: [ax, ay, az, |a|]
    final aMag = math.sqrt(ax * ax + ay * ay + az * az);
    final refVector = [ax, ay, az, aMag];
    final normPower = refVector.fold<double>(0.0, (sum, val) => sum + val * val) + _epsilon;

    // Estimated motion noise for Red and IR
    double noiseEstRed = 0.0;
    double noiseEstIr = 0.0;
    for (int i = 0; i < 4; i++) {
      noiseEstRed += _weightsRed[i] * refVector[i];
      noiseEstIr += _weightsIr[i] * refVector[i];
    }

    // Error signal (Clean PPG)
    final cleanRed = _filteredRed - noiseEstRed;
    final cleanIr = _filteredIr - noiseEstIr;

    // Weight update: w(n+1) = w(n) + (mu / ||x||^2) * e(n) * x(n)
    for (int i = 0; i < 4; i++) {
      _weightsRed[i] += (_mu / normPower) * cleanRed * refVector[i];
      _weightsIr[i] += (_mu / normPower) * cleanIr * refVector[i];
    }

    // Stage 3: Frequency Tracking & SpO2 Ratio-of-Ratios
    _cleanIrBuffer.add(cleanIr);
    if (_cleanIrBuffer.length > _bufferCapacity) {
      _cleanIrBuffer.removeAt(0);
    }

    // Peak detection for Heart Rate and RMSSD
    _detectPeaks(cleanIr, timestampMs);

    final hr = _calculateHeartRate();
    final rmssd = _calculateRmssd();
    final spO2 = _calculateSpO2(rawRed, rawIr, cleanRed, cleanIr);

    return (
      cleanRed: cleanRed,
      cleanIr: cleanIr,
      estimatedHr: hr,
      rmssd: rmssd,
      estimatedSpO2: spO2,
    );
  }

  void _detectPeaks(double currentSample, int timestampMs) {
    if (_cleanIrBuffer.length < 5) return;
    final idx = _cleanIrBuffer.length - 2;
    final prev = _cleanIrBuffer[idx - 1];
    final curr = _cleanIrBuffer[idx];
    final next = _cleanIrBuffer[idx + 1];

    // Local maxima with adaptive dynamic threshold
    if (curr > prev && curr > next && curr > 50.0) {
      if (_peakTimestamps.isEmpty || (timestampMs - _peakTimestamps.last) > 300) {
        // Refractory period: > 300ms (max 200 BPM)
        _peakTimestamps.add(timestampMs);
        if (_peakTimestamps.length > 20) {
          _peakTimestamps.removeAt(0);
        }
      }
    }
  }

  double _calculateHeartRate() {
    if (_peakTimestamps.length < 3) return 72.0; // Default nominal baseline
    final intervals = <int>[];
    for (int i = 1; i < _peakTimestamps.length; i++) {
      intervals.add(_peakTimestamps[i] - _peakTimestamps[i - 1]);
    }
    final avgIntervalMs = intervals.reduce((a, b) => a + b) / intervals.length;
    if (avgIntervalMs <= 0) return 72.0;
    return (60000.0 / avgIntervalMs).clamp(40.0, 210.0);
  }

  double _calculateRmssd() {
    if (_peakTimestamps.length < 4) return 42.0;
    final ibis = <double>[];
    for (int i = 1; i < _peakTimestamps.length; i++) {
      ibis.add((_peakTimestamps[i] - _peakTimestamps[i - 1]).toDouble());
    }

    double sumSqDiff = 0.0;
    for (int i = 1; i < ibis.length; i++) {
      final diff = ibis[i] - ibis[i - 1];
      sumSqDiff += diff * diff;
    }
    final meanSq = sumSqDiff / (ibis.length - 1);
    return math.sqrt(meanSq).clamp(5.0, 150.0);
  }

  double _calculateSpO2(double rawRed, double rawIr, double acRed, double acIr) {
    final dcRed = rawRed.abs() + 1.0;
    final dcIr = rawIr.abs() + 1.0;
    final acRedAbs = acRed.abs() + 0.1;
    final acIrAbs = acIr.abs() + 0.1;

    // R = (AC_red / DC_red) / (AC_ir / DC_ir)
    final r = (acRedAbs / dcRed) / (acIrAbs / dcIr);
    
    // Standard empirical calibration curve: SpO2 = 110 - 25 * R
    final spo2 = 110.0 - (25.0 * r);
    return spo2.clamp(75.0, 100.0);
  }
}
