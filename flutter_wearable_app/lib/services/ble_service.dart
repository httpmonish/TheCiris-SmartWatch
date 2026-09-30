import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants.dart';
import '../core/ble/ble_mock_simulator.dart';
import '../models/sensor_reading.dart';
import '../algorithms/ppg/shin_cho_motion_cancellation.dart';

enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
}

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal() {
    _simulator = MockBleHardwareSimulator();
  }

  late final MockBleHardwareSimulator _simulator;
  final ShinChoPpgProcessor _shinChoProcessor = ShinChoPpgProcessor();
  
  BleConnectionState connectionState = BleConnectionState.connected;
  bool isUsingSimulation = true;
  String connectedDeviceName = "Aegis-Watch-ESP32 (Synthetic Active)";

  StreamController<SensorReading>? _telemetryController;
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _telemetryCharacteristic;
  BluetoothCharacteristic? _oledSyncCharacteristic;
  StreamSubscription? _bleScanSub;
  StreamSubscription? _bleNotifySub;

  final List<ScanResult> scanResults = [];

  Stream<SensorReading> get readingStream {
    _telemetryController ??= StreamController<SensorReading>.broadcast(
      onListen: _startStreaming,
      onCancel: _stopStreaming,
    );
    return _telemetryController!.stream;
  }

  /// Request runtime permissions for Android 12+ (API 31+) & iOS
  Future<bool> requestBlePermissions() async {
    final scanStatus = await Permission.bluetoothScan.request();
    final connectStatus = await Permission.bluetoothConnect.request();
    final locationStatus = await Permission.locationWhenInUse.request();

    return scanStatus.isGranted && connectStatus.isGranted && locationStatus.isGranted;
  }

  void _startStreaming() {
    if (isUsingSimulation) {
      _simulator.telemetryStream.listen((raw) {
        final ppgFiltered = _shinChoProcessor.processSample(
          rawRed: raw.ppgRed.toDouble(),
          rawIr: raw.ppgIr.toDouble(),
          ax: raw.accelX,
          ay: raw.accelY,
          az: raw.accelZ,
          timestampMs: raw.timestampMs,
        );

        final reading = SensorReading(
          timestampMs: raw.timestampMs,
          ppgRed: raw.ppgRed,
          ppgIr: raw.ppgIr,
          heartRate: ppgFiltered.estimatedHr,
          rmssd: ppgFiltered.rmssd,
          spO2: ppgFiltered.estimatedSpO2,
          accelX: raw.accelX,
          accelY: raw.accelY,
          accelZ: raw.accelZ,
          ambientTempC: raw.ambientTempC,
          ambientHumidity: raw.ambientHumidity,
          skinTempC: raw.skinTempC,
          pressureHpa: raw.pressureHpa,
          batteryMillivolts: raw.batteryMillivolts,
          batteryPercentage: ((raw.batteryMillivolts - 3300) / 9.0).round().clamp(0, 100),
          panicButtonPressed: raw.panicButtonPressed,
          solarCharging: raw.solarCharging,
        );

        _telemetryController?.add(reading);
      });
    }
  }

  void _stopStreaming() {}

  /// Start BLE scanning for physical hardware
  Future<void> startScan() async {
    await requestBlePermissions();
    scanResults.clear();
    connectionState = BleConnectionState.scanning;

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 8),
      withServices: [Guid(AppConstants.serviceUuid)],
    );

    _bleScanSub?.cancel();
    _bleScanSub = FlutterBluePlus.scanResults.listen((results) {
      scanResults.clear();
      scanResults.addAll(results);
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    connectionState = _connectedDevice != null ? BleConnectionState.connected : BleConnectionState.disconnected;
  }

  /// Connect to physical BLE watch
  Future<void> connectToHardware(BluetoothDevice device) async {
    connectionState = BleConnectionState.connecting;
    await device.connect(autoConnect: false);
    _connectedDevice = device;
    connectedDeviceName = device.platformName.isNotEmpty ? device.platformName : device.remoteId.str;
    isUsingSimulation = false;
    connectionState = BleConnectionState.connected;

    // Discover Services
    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid == Guid(AppConstants.serviceUuid)) {
        for (final char in service.characteristics) {
          if (char.uuid == Guid(AppConstants.telemetryCharUuid)) {
            _telemetryCharacteristic = char;
            await char.setNotifyValue(true);
            _bleNotifySub?.cancel();
            _bleNotifySub = char.onValueReceived.listen((bytes) {
              if (bytes.length >= 28) {
                final reading = SensorReading.fromBleBytes(Uint8List.fromList(bytes));
                _telemetryController?.add(reading);
              }
            });
          } else if (char.uuid == Guid(AppConstants.oledSyncCharUuid)) {
            _oledSyncCharacteristic = char;
          }
        }
      }
    }
  }

  /// Write 4-byte display payload back to physical Watch OLED characteristic
  Future<void> writeOledPayload(Uint8List payload) async {
    if (_oledSyncCharacteristic != null && !isUsingSimulation) {
      await _oledSyncCharacteristic!.write(payload, withoutResponse: true);
    }
  }

  void setSimulationScenario(SimulationScenario scenario) {
    isUsingSimulation = true;
    _simulator.setScenario(scenario);
  }

  void disconnect() {
    _bleNotifySub?.cancel();
    _connectedDevice?.disconnect();
    _connectedDevice = null;
    connectionState = BleConnectionState.disconnected;
  }
}
