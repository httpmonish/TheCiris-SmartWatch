import 'dart:typed_data';

/// Unpacked raw sensor telemetry packet received over BLE
class RawSensorTelemetry {
  final int timestampMs;
  final int ppgRed;
  final int ppgIr;
  final double accelX; // m/s^2
  final double accelY; // m/s^2
  final double accelZ; // m/s^2
  final double ambientTempC;
  final double ambientHumidity;
  final double skinTempC;
  final double pressureHpa;
  final int batteryMillivolts;
  final bool panicButtonPressed;
  final bool solarCharging;

  const RawSensorTelemetry({
    required this.timestampMs,
    required this.ppgRed,
    required this.ppgIr,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.ambientTempC,
    required this.ambientHumidity,
    required this.skinTempC,
    required this.pressureHpa,
    required this.batteryMillivolts,
    required this.panicButtonPressed,
    required this.solarCharging,
  });

  /// Decodes 28-byte packed binary payload from ESP32/nRF52 firmware
  factory RawSensorTelemetry.fromBytes(Uint8List bytes) {
    if (bytes.length < 28) {
      throw FormatException('Telemetry packet too short: expected 28 bytes, got ${bytes.length}');
    }

    final data = ByteData.sublistView(bytes);

    // [0-3]: Timestamp ms (uint32)
    final timestamp = data.getUint32(0, Endian.little);
    
    // [4-7]: PPG Red (uint32), [8-11]: PPG IR (uint32)
    final ppgRed = data.getUint32(4, Endian.little);
    final ppgIr = data.getUint32(8, Endian.little);

    // [12-17]: Accel X, Y, Z (int16 * 0.000244 * 9.80665)
    final ax = data.getInt16(12, Endian.little) * 0.000244 * 9.80665;
    final ay = data.getInt16(14, Endian.little) * 0.000244 * 9.80665;
    final az = data.getInt16(16, Endian.little) * 0.000244 * 9.80665;

    // [18-21]: SHT31 Ambient Temp (int16 * 0.01) + Humidity (uint16 * 0.01)
    final ambTemp = data.getInt16(18, Endian.little) / 100.0;
    final ambHum = data.getUint16(20, Endian.little) / 100.0;

    // [22-23]: MAX30208 Skin Temp (int16 * 0.005)
    final skinTemp = data.getInt16(22, Endian.little) * 0.005;

    // [24-25]: BME280 Pressure (uint16 + 900.0 hPa offset)
    final pressure = 900.0 + (data.getUint16(24, Endian.little) / 10.0);

    // [26]: Battery (uint8 * 10 + 3000 mV)
    final vBat = 3000 + (data.getUint8(26) * 10);

    // [27]: Flags (Bit 0: SOS, Bit 1: Solar STAT)
    final flags = data.getUint8(27);
    final panic = (flags & 0x01) != 0;
    final solar = (flags & 0x02) != 0;

    return RawSensorTelemetry(
      timestampMs: timestamp,
      ppgRed: ppgRed,
      ppgIr: ppgIr,
      accelX: ax,
      accelY: ay,
      accelZ: az,
      ambientTempC: ambTemp,
      ambientHumidity: ambHum,
      skinTempC: skinTemp,
      pressureHpa: pressure,
      batteryMillivolts: vBat,
      panicButtonPressed: panic,
      solarCharging: solar,
    );
  }
}
