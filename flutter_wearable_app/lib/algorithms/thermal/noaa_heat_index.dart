import 'dart:math' as math;

enum HeatIndexBand {
  safe,            // < 27°C / 80°F
  caution,         // 27 - 32°C (80 - 90°F): Fatigue possible
  extremeCaution,  // 32 - 41°C (90 - 105°F): Heat cramps / exhaustion
  danger,          // 41 - 54°C (105 - 130°F): Heat exhaustion likely
  extremeDanger,   // >= 54°C (>= 130°F): Heat stroke imminent
}

class NOAAHeatIndexEngine {
  /// Computes NOAA/IMD Heat Index using Rothfusz 9-parameter regression equation
  static double computeHeatIndexCelsius(double tempC, double relativeHumidityPct) {
    final tF = (tempC * 9.0 / 5.0) + 32.0;
    final rh = relativeHumidityPct;

    // Simple Steadman formula approximation
    double hiF = 0.5 * (tF + 61.0 + ((tF - 68.0) * 1.2) + (rh * 0.094));

    if (hiF >= 80.0) {
      // Rothfusz regression
      hiF = -42.379 +
          (2.04901523 * tF) +
          (10.14333127 * rh) -
          (0.22475541 * tF * rh) -
          (0.00683783 * tF * tF) -
          (0.05481717 * rh * rh) +
          (0.00122874 * tF * tF * rh) +
          (0.00085282 * tF * rh * rh) -
          (0.00000199 * tF * tF * rh * rh);

      // Low RH adjustment (< 13% and 80°F <= T <= 112°F)
      if (rh < 13.0 && tF >= 80.0 && tF <= 112.0) {
        final adj = ((13.0 - rh) / 4.0) * math.sqrt((17.0 - (tF - 95.0).abs()) / 17.0);
        hiF -= adj;
      }
      // High RH adjustment (> 85% and 80°F <= T <= 87°F)
      else if (rh > 85.0 && tF >= 80.0 && tF <= 87.0) {
        final adj = ((rh - 85.0) / 10.0) * ((87.0 - tF) / 5.0);
        hiF += adj;
      }
    }

    return (hiF - 32.0) * 5.0 / 9.0;
  }

  static HeatIndexBand getHeatIndexBand(double heatIndexC) {
    if (heatIndexC >= 54.0) return HeatIndexBand.extremeDanger;
    if (heatIndexC >= 41.0) return HeatIndexBand.danger;
    if (heatIndexC >= 32.0) return HeatIndexBand.extremeCaution;
    if (heatIndexC >= 27.0) return HeatIndexBand.caution;
    return HeatIndexBand.safe;
  }
}
