import '../core/constants.dart';
import '../models/risk_result.dart';
import '../models/sensor_reading.dart';
import 'heat_index_service.dart';
import 'motion_service.dart';
import 'ml_service.dart';

class RiskEngine {
  /// 5-Signal Risk Fusion Engine with Clinical Tier Floors & NEWS2 Multi-Parameter Escalation
  static RiskResult computeRisk({
    required SensorReading reading,
    required MotionPhase motionPhase,
    required MLInferenceResult mlResult,
    required double heatIndexC,
  }) {
    final alerts = <String>[];

    // Priority 1: Critical Overrides (Manual Panic SOS, Confirmed Fall, Severe Hypoxia)
    if (reading.panicButtonPressed) {
      alerts.add('MANUAL SOS PANIC BUTTON ACTIVATED');
      return const RiskResult(
        compositeScore: 1.0,
        tier: RiskTier.criticalRed,
        statusTitle: 'EMERGENCY SOS',
        primaryReason: 'MANUAL PANIC BUTTON PRESSED',
        activeAlerts: ['MANUAL SOS PANIC BUTTON ACTIVATED'],
        requiresEmergencyEscalation: true,
        cardiacRisk: 1.0,
        fallRisk: 0.0,
        heatRisk: 0.0,
        thermalDeltaRisk: 0.0,
        hypoxiaRisk: 0.0,
      );
    }

    if (motionPhase == MotionPhase.confirmedFall) {
      alerts.add('CONFIRMED FALL / IMMOBILITY REGISTERED');
      return const RiskResult(
        compositeScore: 1.0,
        tier: RiskTier.criticalRed,
        statusTitle: 'MAN-DOWN DETECTED',
        primaryReason: 'CONFIRMED FALL (NO MOVEMENT)',
        activeAlerts: ['CONFIRMED FALL / IMMOBILITY REGISTERED'],
        requiresEmergencyEscalation: true,
        cardiacRisk: 0.0,
        fallRisk: 1.0,
        heatRisk: 0.0,
        thermalDeltaRisk: 0.0,
        hypoxiaRisk: 0.0,
      );
    }

    if (reading.spO2 < AppConstants.spo2CriticalLow) {
      alerts.add('CRITICAL HYPOXEMIA: SpO2 < 90%');
      return RiskResult(
        compositeScore: 1.0,
        tier: RiskTier.criticalRed,
        statusTitle: 'CRITICAL HYPOXIA',
        primaryReason: 'SEVERE HYPOXEMIA DETECTED (SpO2 < 90%)',
        activeAlerts: ['CRITICAL HYPOXEMIA: SpO2 < 90%'],
        requiresEmergencyEscalation: true,
        cardiacRisk: mlResult.anomalyProbability,
        fallRisk: 0.0,
        heatRisk: 0.0,
        thermalDeltaRisk: 0.0,
        hypoxiaRisk: 1.0,
      );
    }

    // 1. sFall: Transient impact spike
    double sFall = (motionPhase == MotionPhase.impactRegistered) ? 0.70 : 0.0;
    if (sFall > 0) alerts.add('Impact Spike registered; monitoring state');

    // 2. sCardiac: Directly from ML Softmax probability P(Anomaly)
    double sCardiac = mlResult.anomalyProbability;
    if (mlResult.type != AnomalyType.normal) {
      alerts.add('ML Engine: ${mlResult.diagnostic}');
    }

    // 3. sHypoxia: Clinical Piecewise Hypoxia Scale
    double sHypoxia = 0.0;
    if (reading.spO2 < AppConstants.spo2WarningLow) {
      sHypoxia = 0.60; // Moderate hypoxemia (90-94%)
      alerts.add('Moderate oxygen saturation drop (SpO2: ${reading.spO2.toStringAsFixed(1)}%)');
    }

    // 4. sHeat: Continuous mapping from NOAA Heat Index
    final heatBand = HeatIndexService.categorize(heatIndexC);
    double sHeat = switch (heatBand) {
      HeatRiskBand.extremeDanger => 1.0,
      HeatRiskBand.danger => 0.75,
      HeatRiskBand.extremeCaution => 0.45,
      HeatRiskBand.caution => 0.20,
      HeatRiskBand.safe => 0.0,
    };
    if (sHeat >= 0.75) alerts.add('High environmental heat stress (HI: ${heatIndexC.toStringAsFixed(1)}°C)');

    // 5. sSkinDelta: Thermoregulatory failure gradient
    final delta = (reading.skinTempC - reading.ambientTempC).abs();
    double sSkinDelta = 0.0;
    if (reading.skinTempC >= AppConstants.skinTempCritical || (reading.skinTempC > 38.0 && delta < 2.0)) {
      sSkinDelta = 1.0;
      alerts.add('Thermoregulatory failure / extreme fever (T_skin: ${reading.skinTempC.toStringAsFixed(1)}°C)');
    } else if (reading.skinTempC >= AppConstants.skinTempFever) {
      sSkinDelta = 0.50;
      alerts.add('Elevated body skin temperature (T_skin: ${reading.skinTempC.toStringAsFixed(1)}°C)');
    }

    // Rebalanced Clinical Weights (Sum = 1.00)
    const double wFall = 0.30;
    const double wCardiac = 0.25;
    const double wHypoxia = 0.20;
    const double wHeat = 0.15;
    const double wSkinDelta = 0.10;

    final composite = (wFall * sFall) +
        (wCardiac * sCardiac) +
        (wHypoxia * sHypoxia) +
        (wHeat * sHeat) +
        (wSkinDelta * sSkinDelta);

    final clamped = composite.clamp(0.0, 1.0);

    // Multi-System Elevation Count
    final elevatedCount = [sCardiac >= 0.50, sHeat >= 0.50, sSkinDelta >= 0.50, sHypoxia >= 0.50].where((b) => b).length;

    // Clinical NEWS2-aligned tier thresholds with Moderate Hypoxia Floor
    RiskTier tier;
    bool escalate = false;
    String title;
    String reason = 'All parameters nominal';

    if (clamped >= 0.65 || sCardiac >= 0.85) {
      tier = RiskTier.criticalRed;
      escalate = true;
      title = 'CRITICAL HEALTH ALERT';
      reason = alerts.isNotEmpty ? alerts.first : 'MULTIPLE VITALS BREACHED';
    } else if (clamped >= 0.30 || elevatedCount >= 2) {
      tier = RiskTier.warningOrange;
      title = 'WARNING: HIGH STRAIN';
      reason = alerts.isNotEmpty ? alerts.first : 'ELEVATED MULTI-SYSTEM STRAIN';
    } else if (clamped >= 0.15 || sHypoxia >= 0.50) {
      // Clinical Floor: Moderate hypoxia is guaranteed at least CAUTION_YELLOW
      tier = RiskTier.cautionYellow;
      title = 'CAUTION: MONITORING';
      reason = sHypoxia >= 0.50
          ? 'MODERATE HYPOXIA EARLY WARNING (SpO2: ${reading.spO2.toStringAsFixed(1)}%)'
          : (alerts.isNotEmpty ? alerts.first : 'MILD STRAIN DETECTED');
    } else {
      tier = RiskTier.nominalGreen;
      title = 'NOMINAL STATE';
    }

    return RiskResult(
      compositeScore: clamped,
      tier: tier,
      statusTitle: title,
      primaryReason: reason,
      activeAlerts: alerts,
      requiresEmergencyEscalation: escalate,
      cardiacRisk: sCardiac,
      fallRisk: sFall,
      heatRisk: sHeat,
      thermalDeltaRisk: sSkinDelta,
      hypoxiaRisk: sHypoxia,
    );
  }
}
