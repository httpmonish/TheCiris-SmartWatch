import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'ble_packet_decoder.dart';

enum SimulationScenario {
  normalResting,
  cardiacAnomalyTachycardia,
  hypoxiaEvent,
  heatStressExtreme,
  fallImpactEvent,
  panicSosPressed,
}

/// Generates realistic 28-byte binary BLE telemetry frames @ 20-50 Hz
class MockBleHardwareSimulator {
  SimulationScenario currentScenario = SimulationScenario.normalResting;
  StreamController<RawSensorTelemetry>? _streamController;
  Timer? _timer;
  int _tickCount = 0;

  Stream<RawSensorTelemetry> get telemetryStream {
    _streamController ??= StreamController<RawSensorTelemetry>.broadcast(
      onListen: _startStream,
      onCancel: _stopStream,
    );
    return _streamController!.stream;
  }

  void setScenario(SimulationScenario scenario) {
    currentScenario = scenario;
    _tickCount = 0;
  }

  void _startStream() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _tickCount++;
      final packet = _generateSyntheticPacket(_tickCount);
      _streamController?.add(packet);
    });
  }

  void _stopStream() {
    _timer?.cancel();
  }

  RawSensorTelemetry _generateSyntheticPacket(int tick) {
    final tSec = tick * 0.05;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Baseline physiological waveforms
    double hr = 72.0;
    double spo2 = 98.0;
    double skinTemp = 34.2;
    double ambTemp = 26.5;
    double ambHum = 45.0;
    double pressure = 1013.25;
    int vBat = 3950;
    bool panic = false;
    bool solar = true;

    // IMU 3-axis
    double ax = 0.1 * math.sin(tSec * 2);
    double ay = 0.1 * math.cos(tSec * 2);
    double az = 9.81 + (0.05 * math.sin(tSec * 4));

    switch (currentScenario) {
      case SimulationScenario.normalResting:
        hr = 70.0 + 3.0 * math.sin(tSec * 0.1);
        spo2 = 98.2;
        break;

      case SimulationScenario.cardiacAnomalyTachycardia:
        hr = 155.0 + 10.0 * math.sin(tSec * 0.5); // Resting severe tachycardia
        spo2 = 94.0;
        break;

      case SimulationScenario.hypoxiaEvent:
        hr = 108.0;
        spo2 = 86.5; // Critical hypoxia
        break;

      case SimulationScenario.heatStressExtreme:
        ambTemp = 42.0;
        ambHum = 75.0;
        skinTemp = 39.4; // Hyperthermia
        hr = 125.0;
        break;

      case SimulationScenario.fallImpactEvent:
        if (tick >= 20 && tick < 30) {
          // Free fall phase (< 0.5g)
          ax = 0.5;
          ay = 0.3;
          az = 1.2;
        } else if (tick >= 30 && tick < 38) {
          // Impact spike (> 3.5g)
          ax = 12.0;
          ay = 18.0;
          az = 32.0;
          pressure = 1013.38; // Floor proximity height drop
        } else if (tick >= 38) {
          // Post-fall immobility on ground
          ax = 0.02;
          ay = 9.80; // lying on side
          az = 0.05;
        }
        break;

      case SimulationScenario.panicSosPressed:
        panic = true;
        break;
    }

    // Generate realistic PPG waveform pulse
    final ppgPulse = math.exp(-math.pow((tSec % (60.0 / hr)) * 5.0 - 1.2, 2));
    final ppgRed = (50000 + (ppgPulse * 15000) + (math.Random().nextDouble() * 200)).toInt();
    final ppgIr = (75000 + (ppgPulse * 22000) + (math.Random().nextDouble() * 300)).toInt();

    // Pack into raw bytes to guarantee decoder verification
    final bytes = Uint8List(28);
    final data = ByteData.sublistView(bytes);

    data.setUint32(0, timestamp & 0xFFFFFFFF, Endian.little);
    data.setUint32(4, ppgRed, Endian.little);
    data.setUint32(8, ppgIr, Endian.little);
    data.setInt16(12, (ax / (0.000244 * 9.80665)).round(), Endian.little);
    data.setInt16(14, (ay / (0.000244 * 9.80665)).round(), Endian.little);
    data.setInt16(16, (az / (0.000244 * 9.80665)).round(), Endian.little);
    data.setInt16(18, (ambTemp * 100).round(), Endian.little);
    data.setUint16(20, (ambHum * 100).round(), Endian.little);
    data.setInt16(22, (skinTemp / 0.005).round(), Endian.little);
    data.setUint16(24, ((pressure - 900.0) * 10).round(), Endian.little);
    data.setUint8(26, ((vBat - 3000) ~/ 10).clamp(0, 255));
    data.setUint8(27, (panic ? 1 : 0) | (solar ? 2 : 0));

    // Decode through production binary decoder
    return RawSensorTelemetry.fromBytes(bytes);
  }

  void dispose() {
    _timer?.cancel();
    _streamController?.close();
  }
}
