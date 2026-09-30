import 'dart:async';
import 'dart:typed_data';
import 'ble_packet_decoder.dart';
import 'ble_mock_simulator.dart';

class BleHardwareService {
  final MockBleHardwareSimulator simulator = MockBleHardwareSimulator();
  bool useMockSimulation = true;

  Stream<RawSensorTelemetry> get telemetryStream {
    if (useMockSimulation) {
      return simulator.telemetryStream;
    }
    // Real BLE characteristic stream hook
    return simulator.telemetryStream;
  }

  /// Write 4-byte display payload back to Watch OLED characteristic
  Future<void> writeOledSyncPayload(Uint8List payload) async {
    // In hardware mode: write without response to UUID 0000FF02-...
    // print('Synced to OLED: ${payload.toList()}');
  }

  void switchScenario(SimulationScenario scenario) {
    simulator.setScenario(scenario);
  }
}
