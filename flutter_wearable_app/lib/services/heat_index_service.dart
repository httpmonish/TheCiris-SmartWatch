import 'dart:math' as math;

enum HeatRiskBand {
  safe,
  caution,
  extremeCaution,
  danger,
  extremeDanger,
}

class HeatIndexService {
  /// Pure function: Computes NOAA / IMD Heat Index in Celsius using Rothfusz regression
  static double computeHeatIndex(double tempC, double relativeHumidityPct) {
    final tF = (tempC * 9.0 / 5.0) + 32.0;
    final rh = relativeHumidityPct;

    // Steadman baseline test
    double hiF = 0.5 * (tF + 61.0 + ((tF - 68.0) * 1.2) + (rh * 0.094));

    if (hiF >= 80.0) {
      hiF = -42.379 +
          (2.04901523 * tF) +
          (10.14333127 * rh) -
          (0.22475541 * tF * rh) -
          (0.00683783 * tF * tF) -
          (0.05481717 * rh * rh) +
          (0.00122874 * tF * tF * rh) +
          (0.00085282 * tF * rh * rh) -
          (0.00000199 * tF * tF * rh * rh);

      if (rh < 13.0 && tF >= 80.0 && tF <= 112.0) {
        final adj = ((13.0 - rh) / 4.0) * math.sqrt((17.0 - (tF - 95.0).abs()) / 17.0);
        hiF -= adj;
      } else if (rh > 85.0 && tF >= 80.0 && tF <= 87.0) {
        final adj = ((rh - 85.0) / 10.0) * ((87.0 - tF) / 5.0);
        hiF += adj;
      }
    }

    return (hiF - 32.0) * 5.0 / 9.0;
  }

  static HeatRiskBand categorize(double heatIndexC) {
    if (heatIndexC >= 54.0) return HeatRiskBand.extremeDanger;
    if (heatIndexC >= 41.0) return HeatRiskBand.danger;
    if (heatIndexC >= 32.0) return HeatRiskBand.extremeCaution;
    if (heatIndexC >= 27.0) return HeatRiskBand.caution;
    return HeatRiskBand.safe;
  }
}
