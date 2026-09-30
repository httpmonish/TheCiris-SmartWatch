import '../ppg/shin_cho_motion_cancellation.dart';
import '../ml/cardiac_anomaly_classifier.dart';
import '../fall_detection/bmi270_fall_detector.dart';
import '../thermal/noaa_heat_index.dart';
import '../thermal/skin_ambient_differential.dart';
import '../power/battery_solar_parser.dart';

enum RiskTier {
  nominalGreen,   // 0.00 - 0.30
  cautionYellow,  // 0.31 - 0.60
  warningOrange,  // 0.61 - 0.79
  criticalRed,    // 0.80 - 1.00 (Triggers SOS timer / Haptic Alert)
}

class FusedRiskAssessment {
  final double compositeScore; // 0.0 to 1.0
  final RiskTier riskTier;
  final String primaryRiskReason;
  final List<String> activeAlerts;
  final bool requiresEmergencyEscalation;

  const FusedRiskAssessment({
    required this.compositeScore,
    required this.riskTier,
    required this.primaryRiskReason,
    required this.activeAlerts,
    required this.requiresEmergencyEscalation,
  });
}

class CompositeRiskEngine {
  // Weights distribution (Sum = 1.00)
  static const double wFall = 0.35;
  static const double wCardiac = 0.25;
  static const double wHeat = 0.20;
  static const double wSkinDelta = 0.10;
  static const double wHypoxia = 0.10;

  /// Full Multi-Sensor Weighted Risk Fusion Engine
  static FusedRiskAssessment evaluate({
    required FallDetectionState fallState,
    required CardiacAnomalyResult cardiacResult,
    required HeatIndexBand heatBand,
    required SkinThermalState thermalState,
    required double spO2,
    required bool isSosButtonPressed,
  }) {
    final alerts = <String>[];

    // Priority 1: Immediate Critical Overrides (Fall or Manual Panic Button)
    if (isSosButtonPressed) {
      alerts.add('MANUAL SOS PANIC BUTTON DEPRESSED');
      return const FusedRiskAssessment(
        compositeScore: 1.0,
        riskTier: RiskTier.criticalRed,
        primaryRiskReason: 'MANUAL EMERGENCY SOS ACTIVATED',
        activeAlerts: ['MANUAL SOS PANIC BUTTON DEPRESSED'],
        requiresEmergencyEscalation: true,
      );
    }

    if (fallState == FallDetectionState.confirmedFallManDown) {
      alerts.add('CONFIRMED MAN-DOWN / FALL IMPACT REGISTERED');
      return const FusedRiskAssessment(
        compositeScore: 1.0,
        riskTier: RiskTier.criticalRed,
        primaryRiskReason: 'MAN-DOWN FALL DETECTED (NO MOVEMENT)',
        activeAlerts: ['CONFIRMED MAN-DOWN / FALL IMPACT REGISTERED'],
        requiresEmergencyEscalation: true,
      );
    }

    // Component Score 1: Fall / Impact sub-score
    double sFall = 0.0;
    if (fallState == FallDetectionState.impactRegistered) {
      sFall = 0.70;
      alerts.add('High G-force impact detected; monitoring for recovery');
    } else if (fallState == FallDetectionState.freeFallDetected) {
      sFall = 0.30;
    }

    // Component Score 2: ML Cardiac Anomaly sub-score
    double sCardiac = 0.0;
    if (cardiacResult.classification == CardiacAnomalyClass.criticalCardiacAnomaly) {
      sCardiac = 1.0;
      alerts.add('ML Cardiac Classifier: ${cardiacResult.diagnostic}');
    } else if (cardiacResult.classification == CardiacAnomalyClass.physiologicalStrain) {
      sCardiac = 0.50;
      alerts.add('ML Classifier: Cardiovascular strain elevated');
    }

    // Component Score 3: NOAA Heat Index sub-score
    double sHeat = switch (heatBand) {
      HeatIndexBand.extremeDanger => 1.0,
      HeatIndexBand.danger => 0.75,
      HeatIndexBand.extremeCaution => 0.45,
      HeatIndexBand.caution => 0.20,
      HeatIndexBand.safe => 0.0,
    };
    if (sHeat >= 0.75) {
      alerts.add('Ambient Heat Index at dangerous thresholds');
    }

    // Component Score 4: Skin-Ambient Differential sub-score
    double sSkinDelta = switch (thermalState) {
      SkinThermalState.severeHeatStrokeRisk => 1.0,
      SkinThermalState.mildHyperthermia => 0.60,
      SkinThermalState.hypothermiaRisk => 0.70,
      SkinThermalState.nominalThermoregulation => 0.0,
    };
    if (sSkinDelta >= 0.60) {
      alerts.add('Skin-ambient thermal dissipation compromised');
    }

    // Component Score 5: Direct SpO2 Hypoxia sub-score
    double sHypoxia = 0.0;
    if (spO2 < 90.0) {
      sHypoxia = 1.0;
      alerts.add('Critical Hypoxemia (SpO2: ${spO2.toStringAsFixed(1)}%)');
    } else if (spO2 < 94.0) {
      sHypoxia = 0.50;
      alerts.add('Moderate oxygen saturation drop (SpO2: ${spO2.toStringAsFixed(1)}%)');
    }

    // Compute Weighted Normalized Sum
    final composite = (wFall * sFall) +
        (wCardiac * sCardiac) +
        (wHeat * sHeat) +
        (wSkinDelta * sSkinDelta) +
        (wHypoxia * sHypoxia);

    final clampedComposite = composite.clamp(0.0, 1.0);

    // Determine Risk Tier
    RiskTier tier;
    bool escalate = false;
    String primaryReason = 'All parameters nominal';

    if (clampedComposite >= 0.75 || sCardiac == 1.0 || sHypoxia == 1.0) {
      tier = RiskTier.criticalRed;
      escalate = true;
      primaryReason = alerts.isNotEmpty ? alerts.first : 'MULTIPLE CRITICAL VITALS BREACHED';
    } else if (clampedComposite >= 0.50) {
      tier = RiskTier.warningOrange;
      primaryReason = alerts.isNotEmpty ? alerts.first : 'ELEVATED CARDIO-THERMAL STRAIN';
    } else if (clampedComposite >= 0.25) {
      tier = RiskTier.cautionYellow;
      primaryReason = alerts.isNotEmpty ? alerts.first : 'MILD ENVIRONMENTAL/PHYSIOLOGICAL STRAIN';
    } else {
      tier = RiskTier.nominalGreen;
    }

    return FusedRiskAssessment(
      compositeScore: clampedComposite,
      riskTier: tier,
      primaryRiskReason: primaryReason,
      activeAlerts: alerts,
      requiresEmergencyEscalation: escalate,
    );
  }
}
