enum RiskTier {
  nominalGreen,
  cautionYellow,
  warningOrange,
  criticalRed,
}

class RiskResult {
  final double compositeScore; // 0.0 to 1.0
  final RiskTier tier;
  final String statusTitle;
  final String primaryReason;
  final List<String> activeAlerts;
  final bool requiresEmergencyEscalation;
  final double cardiacRisk;
  final double fallRisk;
  final double heatRisk;
  final double thermalDeltaRisk;
  final double hypoxiaRisk;

  const RiskResult({
    required this.compositeScore,
    required this.tier,
    required this.statusTitle,
    required this.primaryReason,
    required this.activeAlerts,
    required this.requiresEmergencyEscalation,
    required this.cardiacRisk,
    required this.fallRisk,
    required this.heatRisk,
    required this.thermalDeltaRisk,
    required this.hypoxiaRisk,
  });
}
