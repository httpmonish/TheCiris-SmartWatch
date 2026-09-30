import 'dart:typed_data';
import '../algorithms/fusion/composite_risk_engine.dart';

/// Builds the 4-byte response packet to write back to the ESP32/nRF52 watch OLED display
/// over BLE Characteristic UUID `0000FF02-0000-1000-8000-00805F9B34FB`:
///
/// [Byte 0]: Status Code (0: OK, 1: CAUTION, 2: WARNING, 3: CRITICAL/SOS)
/// [Byte 1]: Battery Percentage (0 - 100%)
/// [Byte 2-3]: Scaled Risk Score (uint16, 0 - 1000 representing 0.000 to 1.000)
class OledSyncService {
  static Uint8List serializeOledDisplayPacket({
    required RiskTier tier,
    required int batteryPct,
    required double riskScore,
    required bool isSosActive,
  }) {
    final buffer = Uint8List(4);
    final view = ByteData.sublistView(buffer);

    int statusCode = switch (tier) {
      RiskTier.nominalGreen => 0,
      RiskTier.cautionYellow => 1,
      RiskTier.warningOrange => 2,
      RiskTier.criticalRed => 3,
    };

    if (isSosActive) {
      statusCode = 3;
    }

    view.setUint8(0, statusCode);
    view.setUint8(1, batteryPct.clamp(0, 100));
    view.setUint16(2, (riskScore * 1000).toInt().clamp(0, 1000), Endian.little);

    return buffer;
  }
}
