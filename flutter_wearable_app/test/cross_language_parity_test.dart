import 'package:flutter_test/flutter_test.dart';
import '../lib/services/ml_service.dart';

void main() {
  test('Bit-for-Bit Cross-Language Parity with Python Model Constants', () {
    final testCases = [
      {
        "name": "Nominal Baseline",
        "inputs": [72.0, 48.0, 98.2, 34.2, 25.0, 1.2],
        "expectedType": AnomalyType.normal,
      },
      {
        "name": "Heavy Aerobic Workout",
        "inputs": [145.0, 22.0, 97.0, 35.8, 28.0, 15.0],
        "expectedType": AnomalyType.normal,
      },
      {
        "name": "Environmental Heat Strain",
        "inputs": [122.0, 18.0, 94.5, 38.6, 40.0, 2.8],
        "expectedType": AnomalyType.physiologicalStrain,
      },
      {
        "name": "Resting Tachycardia",
        "inputs": [152.0, 12.0, 95.0, 35.0, 24.0, 0.7],
        "expectedType": AnomalyType.cardiacAnomaly,
      },
      {
        "name": "Severe Hypoxemia",
        "inputs": [110.0, 20.0, 86.5, 34.0, 24.0, 1.0],
        "expectedType": AnomalyType.cardiacAnomaly,
      },
    ];

    for (final tc in testCases) {
      final inps = tc["inputs"] as List<double>;
      final result = MLService.predictAnomaly(
        heartRate: inps[0],
        rmssd: inps[1],
        spO2: inps[2],
        skinTemp: inps[3],
        ambientTemp: inps[4],
        imuJerk: inps[5],
      );

      expect(result.type, tc["expectedType"], reason: "Failed vector: ${tc["name"]}");
    }
  });
}
