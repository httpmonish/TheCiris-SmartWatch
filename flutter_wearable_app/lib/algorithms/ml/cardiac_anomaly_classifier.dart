import 'dart:math' as math;
import 'model_constants.dart';

enum CardiacAnomalyClass {
  normalBaseline,
  physiologicalStrain,
  criticalCardiacAnomaly,
}

class CardiacAnomalyResult {
  final CardiacAnomalyClass classification;
  final double anomalyProbability;
  final List<double> classProbabilities;
  final String diagnostic;

  const CardiacAnomalyResult({
    required this.classification,
    required this.anomalyProbability,
    required this.classProbabilities,
    required this.diagnostic,
  });
}

/// Zero-latency edge ML inference engine using quantized model constants
class CardiacAnomalyClassifier {
  /// Input features:
  /// [0]: Heart Rate (BPM)
  /// [1]: RMSSD (ms)
  /// [2]: SpO2 (%)
  /// [3]: Skin Temp (°C)
  /// [4]: Ambient Temp (°C)
  /// [5]: IMU Jerk / Motion RMS (m/s^3)
  static CardiacAnomalyResult evaluate({
    required double heartRate,
    required double rmssd,
    required double spO2,
    required double skinTemp,
    required double ambientTemp,
    required double imuJerk,
  }) {
    final rawFeatures = [heartRate, rmssd, spO2, skinTemp, ambientTemp, imuJerk];
    final normFeatures = List<double>.filled(6, 0.0);

    // Z-score Normalization using training distribution constants
    for (int i = 0; i < 6; i++) {
      normFeatures[i] = (rawFeatures[i] - MLModelWeights.featureMeans[i]) /
          MLModelWeights.featureStds[i];
    }

    // Linear Forward Pass: logits = norm_x * W + b
    final logits = List<double>.filled(3, 0.0);
    for (int c = 0; c < 3; c++) {
      double sum = MLModelWeights.biases[c];
      for (int f = 0; f < 6; f++) {
        sum += normFeatures[f] * MLModelWeights.weights[f][c];
      }
      logits[c] = sum;
    }

    // Softmax Activation
    final maxLogit = logits.reduce(math.max);
    final expList = logits.map((l) => math.exp(l - maxLogit)).toList();
    final sumExp = expList.reduce((a, b) => a + b);
    final probs = expList.map((e) => e / sumExp).toList();

    // Determine predicted class
    int bestClass = 0;
    double bestProb = probs[0];
    for (int i = 1; i < 3; i++) {
      if (probs[i] > bestProb) {
        bestProb = probs[i];
        bestClass = i;
      }
    }

    switch (bestClass) {
      case 2:
        return CardiacAnomalyResult(
          classification: CardiacAnomalyClass.criticalCardiacAnomaly,
          anomalyProbability: probs[2],
          classProbabilities: probs,
          diagnostic: spO2 < 90.0
              ? 'SEVERE HYPOXIA DETECTED (SpO2 < 90%)'
              : (heartRate > 140
                  ? 'RESTING TACHYCARDIA ANOMALY'
                  : 'BRADYCARDIA / CARDIAC COLLAPSE RISK'),
        );
      case 1:
        return CardiacAnomalyResult(
          classification: CardiacAnomalyClass.physiologicalStrain,
          anomalyProbability: probs[1],
          classProbabilities: probs,
          diagnostic: 'ELEVATED CARDIOVASCULAR / HEAT STRAIN',
        );
      default:
        return CardiacAnomalyResult(
          classification: CardiacAnomalyClass.normalBaseline,
          anomalyProbability: probs[2],
          classProbabilities: probs,
          diagnostic: 'HEMODYNAMICS WITHIN NOMINAL RANGE',
        );
    }
  }
}
