import 'dart:math' as math;
import '../algorithms/ml/model_constants.dart';

enum AnomalyType {
  normal,
  physiologicalStrain,
  cardiacAnomaly,
}

class MLInferenceResult {
  final AnomalyType type;
  final double anomalyProbability;
  final double strainProbability;
  final double confidence;
  final String diagnostic;

  const MLInferenceResult({
    required this.type,
    required this.anomalyProbability,
    required this.strainProbability,
    required this.confidence,
    required this.diagnostic,
  });
}

class MLService {
  /// Zero-latency inference on 10 multi-modal features matching Python 1 Lakh training pipeline
  static MLInferenceResult predictAnomaly({
    required double heartRate,
    required double rmssd,
    required double spO2,
    required double skinTemp,
    required double ambientTemp,
    required double ambientHumidity,
    required double imuJerk,
    double aqi = 45.0,
    double pressureHpa = 1013.25,
    double floodRisk = 0.0,
  }) {
    final raw = [
      heartRate,
      rmssd,
      spO2,
      skinTemp,
      ambientTemp,
      ambientHumidity,
      imuJerk,
      aqi,
      pressureHpa,
      floodRisk,
    ];
    final norm = List<double>.filled(10, 0.0);

    // Z-score Normalization using 100,000-sample trained means and standard deviations
    for (int i = 0; i < 10; i++) {
      norm[i] = (raw[i] - MLModelWeights.featureMeans[i]) / MLModelWeights.featureStds[i];
    }

    // Forward pass: logits = norm_x * W + b
    final logits = List<double>.filled(3, 0.0);
    for (int c = 0; c < 3; c++) {
      double sum = MLModelWeights.biases[c];
      for (int f = 0; f < 10; f++) {
        sum += norm[f] * MLModelWeights.weights[f][c];
      }
      logits[c] = sum;
    }

    // Softmax
    final maxLogit = logits.reduce(math.max);
    final expList = logits.map((l) => math.exp(l - maxLogit)).toList();
    final sumExp = expList.reduce((a, b) => a + b);
    final probs = expList.map((e) => e / sumExp).toList();

    int maxIdx = 0;
    double maxP = probs[0];
    for (int i = 1; i < 3; i++) {
      if (probs[i] > maxP) {
        maxP = probs[i];
        maxIdx = i;
      }
    }

    switch (maxIdx) {
      case 2:
        return MLInferenceResult(
          type: AnomalyType.cardiacAnomaly,
          anomalyProbability: probs[2],
          strainProbability: probs[1],
          confidence: probs[2],
          diagnostic: floodRisk > 0.8
              ? 'FLASH FLOOD WATER INUNDATION RISK'
              : (spO2 < 90.0
                  ? 'CRITICAL HYPOXIA (SpO2 < 90%)'
                  : (heartRate > 140 ? 'RESTING TACHYCARDIA' : 'CARDIAC COLLAPSE RISK')),
        );
      case 1:
        return MLInferenceResult(
          type: AnomalyType.physiologicalStrain,
          anomalyProbability: probs[2],
          strainProbability: probs[1],
          confidence: probs[1],
          diagnostic: aqi > 200
              ? 'TOXIC AIR POLLUTION SPIKE (AQI > 200)'
              : 'ELEVATED ENVIRONMENTAL / HEAT STRAIN',
        );
      default:
        return MLInferenceResult(
          type: AnomalyType.normal,
          anomalyProbability: probs[2],
          strainProbability: probs[1],
          confidence: probs[0],
          diagnostic: 'NOMINAL HEMODYNAMICS',
        );
    }
  }
}
