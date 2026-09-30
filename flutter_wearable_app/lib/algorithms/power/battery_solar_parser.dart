class BatterySolarState {
  final int millivolts;
  final int percentage;
  final bool isSolarCharging;
  final bool isLowBattery;
  final String statusText;

  const BatterySolarState({
    required this.millivolts,
    required this.percentage,
    required this.isSolarCharging,
    required this.isLowBattery,
    required this.statusText,
  });
}

class BatterySolarParser {
  /// Translates CN3065 STAT pin logic + Non-linear LiPo Open Circuit Voltage (OCV) curve
  static BatterySolarState parse({
    required int millivolts,
    required bool solarChargingBit,
  }) {
    // 1S LiPo discharge curve approximation (3.2V cutoff to 4.2V max)
    int percentage;
    if (millivolts >= 4200) {
      percentage = 100;
    } else if (millivolts >= 4000) {
      percentage = 80 + (((millivolts - 4000) / 200) * 20).round();
    } else if (millivolts >= 3800) {
      percentage = 40 + (((millivolts - 3800) / 200) * 40).round();
    } else if (millivolts >= 3600) {
      percentage = 15 + (((millivolts - 3600) / 200) * 25).round();
    } else if (millivolts >= 3300) {
      percentage = (((millivolts - 3300) / 300) * 15).round();
    } else {
      percentage = 0;
    }

    final lowBatt = percentage <= 15;
    final status = solarChargingBit
        ? 'SOLAR CHARGING (${percentage}%)'
        : (lowBatt ? 'LOW BATTERY WARNING (${percentage}%)' : 'BATTERY NOMINAL (${percentage}%)');

    return BatterySolarState(
      millivolts: millivolts,
      percentage: percentage.clamp(0, 100),
      isSolarCharging: solarChargingBit,
      isLowBattery: lowBatt,
      statusText: status,
    );
  }
}
