import 'dart:typed_data';

class SensorReading {
  final int timestampMs;
  final int ppgRed;
  final int ppgIr;
  final double heartRate;
  final double rmssd;
  final double spO2;
  final double accelX;
  final double accelY;
  final double accelZ;
  final double ambientTempC;
  final double ambientHumidity;
  final double skinTempC;
  final double pressureHpa;
  final int batteryMillivolts;
  final int batteryPercentage;
  final bool panicButtonPressed;
  final bool solarCharging;

  const SensorReading({
    required this.timestampMs,
    required this.ppgRed,
    required this.ppgIr,
    required this.heartRate,
    required this.rmssd,
    required this.spO2,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.ambientTempC,
    required this.ambientHumidity,
    required this.skinTempC,
    required this.pressureHpa,
    required this.batteryMillivolts,
    required this.batteryPercentage,
    required this.panicButtonPressed,
    required this.solarCharging,
  });

  /// Binary parser for 28-byte raw BLE packet
  factory SensorReading.fromBleBytes(Uint8List bytes, {double? hr, double? rmssdVal, double? spo2Val}) {
    if (bytes.length < 28) {
      throw FormatException('Malformed telemetry packet: expected 28 bytes, got ${bytes.length}');
    }

    final data = ByteData.sublistView(bytes);
    final timestamp = data.getUint32(0, Endian.little);
    final ppgRed = data.getUint32(4, Endian.little);
    final ppgIr = data.getUint32(8, Endian.little);

    final ax = data.getInt16(12, Endian.little) * 0.000244 * 9.80665;
    final ay = data.getInt16(14, Endian.little) * 0.000244 * 9.80665;
    final az = data.getInt16(16, Endian.little) * 0.000244 * 9.80665;

    final ambTemp = data.getInt16(18, Endian.little) / 100.0;
    final ambHum = data.getUint16(20, Endian.little) / 100.0;
    final skinTemp = data.getInt16(22, Endian.little) * 0.005;
    final pressure = 900.0 + (data.getUint16(24, Endian.little) / 10.0);

    final vBat = 3000 + (data.getUint8(26) * 10);
    final flags = data.getUint8(27);
    final panic = (flags & 0x01) != 0;
    final solar = (flags & 0x02) != 0;

    // Battery OCV percentage curve
    int battPct = 100;
    if (vBat <= 3300) battPct = 0;
    else if (vBat < 4200) battPct = (((vBat - 3300) / 900) * 100).round();

    return SensorReading(
      timestampMs: timestamp,
      ppgRed: ppgRed,
      ppgIr: ppgIr,
      heartRate: hr ?? 72.0,
      rmssd: rmssdVal ?? 45.0,
      spO2: spo2Val ?? 98.0,
      accelX: ax,
      accelY: ay,
      accelZ: az,
      ambientTempC: ambTemp,
      ambientHumidity: ambHum,
      skinTempC: skinTemp,
      pressureHpa: pressure,
      batteryMillivolts: vBat,
      batteryPercentage: battPct.clamp(0, 100),
      panicButtonPressed: panic,
      solarCharging: solar,
    );
  }
}
