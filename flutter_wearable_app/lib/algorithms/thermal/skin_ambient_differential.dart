enum SkinThermalState {
  nominalThermoregulation,
  mildHyperthermia,
  severeHeatStrokeRisk,
  hypothermiaRisk,
}

class SkinAmbientDifferential {
  /// Evaluates physiological thermal gradient between MAX30208 (Skin) and SHT31 (Ambient).
  /// Under normal conditions: T_skin (33-35°C) > T_ambient (20-28°C) by 4-10°C.
  /// When T_ambient > 35°C and T_skin > 38.5°C with delta < 1.5°C, evaporative cooling has collapsed.
  static ({double deltaT, SkinThermalState state, String diagnostic}) evaluate({
    required double skinTempC,
    required double ambientTempC,
  }) {
    final delta = skinTempC - ambientTempC;

    if (skinTempC >= 39.2 || (skinTempC >= 38.0 && ambientTempC >= 36.0 && delta.abs() < 2.0)) {
      return (
        deltaT: delta,
        state: SkinThermalState.severeHeatStrokeRisk,
        diagnostic: 'THERMAL REGULATION COLLAPSE (T_skin: ${skinTempC.toStringAsFixed(1)}°C)',
      );
    } else if (skinTempC >= 37.8 || (ambientTempC > 34.0 && delta < 3.0)) {
      return (
        deltaT: delta,
        state: SkinThermalState.mildHyperthermia,
        diagnostic: 'ELEVATED CORE/SKIN TEMPERATURE GRADIENT',
      );
    } else if (skinTempC < 32.0) {
      return (
        deltaT: delta,
        state: SkinThermalState.hypothermiaRisk,
        diagnostic: 'HYPOTHERMIA RISK (T_skin: ${skinTempC.toStringAsFixed(1)}°C)',
      );
    }

    return (
      deltaT: delta,
      state: SkinThermalState.nominalThermoregulation,
      diagnostic: 'THERMAL GRADIENT NORMAL (Delta: ${delta.toStringAsFixed(1)}°C)',
    );
  }
}
