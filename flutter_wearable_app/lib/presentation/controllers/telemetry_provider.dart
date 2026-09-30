import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/ble/ble_packet_decoder.dart';
import '../../core/ble/ble_service.dart';
import '../../core/ble/ble_mock_simulator.dart';
import '../../algorithms/ppg/shin_cho_motion_cancellation.dart';
import '../../algorithms/ml/cardiac_anomaly_classifier.dart';
import '../../algorithms/fall_detection/bmi270_fall_detector.dart';
import '../../algorithms/thermal/noaa_heat_index.dart';
import '../../algorithms/thermal/skin_ambient_differential.dart';
import '../../algorithms/power/battery_solar_parser.dart';
import '../../algorithms/fusion/composite_risk_engine.dart';
import '../../algorithms/escalation/sos_escalation_manager.dart';
import '../../sync/oled_sync_service.dart';

class ProcessedDashboardState {
  final RawSensorTelemetry raw;
  final double cleanPpgIr;
  final double heartRate;
  final double rmssd;
  final double spO2;
  final CardiacAnomalyResult cardiacAnomaly;
  final FallDetectionState fallState;
  final double heatIndexC;
  final HeatIndexBand heatBand;
  final ({double deltaT, SkinThermalState state, String diagnostic}) skinThermal;
  final BatterySolarState batteryState;
  final FusedRiskAssessment riskAssessment;
  final SosState sosState;
  final int sosCountdownSeconds;
  final List<double> ppgWaveformHistory;

  const ProcessedDashboardState({
    required this.raw,
    required this.cleanPpgIr,
    required this.heartRate,
    required this.rmssd,
    required this.spO2,
    required this.cardiacAnomaly,
    required this.fallState,
    required this.heatIndexC,
    required this.heatBand,
    required this.skinThermal,
    required this.batteryState,
    required this.riskAssessment,
    required this.sosState,
    required this.sosCountdownSeconds,
    required this.ppgWaveformHistory,
  });
}

class TelemetryController extends ChangeNotifier {
  final BleHardwareService bleService = BleHardwareService();
  
  // Member algorithm engines
  final ShinChoPpgProcessor _ppgEngine = ShinChoPpgProcessor();
  final Bmi270FallDetector _fallEngine = Bmi270FallDetector();
  late final SosEscalationManager _sosManager;

  StreamSubscription? _subscription;
  ProcessedDashboardState? currentState;
  final List<double> _ppgBuffer = [];

  TelemetryController() {
    _sosManager = SosEscalationManager(
      onTick: (seconds) {
        notifyListeners();
      },
      onDispatchEmergency: (reason) {
        notifyListeners();
      },
      onHapticRequest: (pattern) {
        // Haptic feedback trigger on mobile
      },
    );

    _initStream();
  }

  void _initStream() {
    _subscription = bleService.telemetryStream.listen(_processIncomingPacket);
  }

  void _processIncomingPacket(RawSensorTelemetry raw) {
    // 1. [Siddhesh] Shin & Cho (2019) Preprocessing + Adaptive NLMS Filter + Frequency Tracking
    final ppgResult = _ppgEngine.processSample(
      rawRed: raw.ppgRed.toDouble(),
      rawIr: raw.ppgIr.toDouble(),
      ax: raw.accelX,
      ay: raw.accelY,
      az: raw.accelZ,
      timestampMs: raw.timestampMs,
    );

    // Waveform history buffer for fl_chart
    _ppgBuffer.add(ppgResult.cleanIr);
    if (_ppgBuffer.length > 80) {
      _ppgBuffer.removeAt(0);
    }

    // 2. [Siddhesh] ML Cardiac Anomaly Classifier
    final imuJerk = (raw.accelX.abs() + raw.accelY.abs() + (raw.accelZ - 9.81).abs());
    final cardiacResult = CardiacAnomalyClassifier.evaluate(
      heartRate: ppgResult.estimatedHr,
      rmssd: ppgResult.rmssd,
      spO2: ppgResult.estimatedSpO2,
      skinTemp: raw.skinTempC,
      ambientTemp: raw.ambientTempC,
      imuJerk: imuJerk,
    );

    // 3. [Farea] BMI270 Fall Detector + BME280 Barometric Pressure Drop
    final fallState = _fallEngine.processSample(
      ax: raw.accelX,
      ay: raw.accelY,
      az: raw.accelZ,
      baroPressureHpa: raw.pressureHpa,
      timestampMs: raw.timestampMs,
    );

    // 4. [Monish] SHT31 NOAA Heat Index
    final heatIndexC = NOAAHeatIndexEngine.computeHeatIndexCelsius(
      raw.ambientTempC,
      raw.ambientHumidity,
    );
    final heatBand = NOAAHeatIndexEngine.getHeatIndexBand(heatIndexC);

    // 5. [Monish] MAX30208 vs SHT31 Skin-Ambient Differential
    final skinThermal = SkinAmbientDifferential.evaluate(
      skinTempC: raw.skinTempC,
      ambientTempC: raw.ambientTempC,
    );

    // 6. [Jainabbi] CN3065 Battery + Solar STAT Parser
    final batteryState = BatterySolarParser.parse(
      millivolts: raw.batteryMillivolts,
      solarChargingBit: raw.solarCharging,
    );

    // 7. [Jainabbi] Step 2: Multi-Sensor Weighted Risk Fusion Engine
    final riskAssessment = CompositeRiskEngine.evaluate(
      fallState: fallState,
      cardiacResult: cardiacResult,
      heatBand: heatBand,
      thermalState: skinThermal.state,
      spO2: ppgResult.estimatedSpO2,
      isSosButtonPressed: raw.panicButtonPressed,
    );

    // 8. [Sadeem] Step 4: SOS Auto-Escalation Check
    if (riskAssessment.requiresEmergencyEscalation &&
        _sosManager.state == SosState.idle) {
      _sosManager.startEscalation(
        reason: riskAssessment.primaryRiskReason,
        isManualPanic: raw.panicButtonPressed,
      );
    }

    // 9. [Musab] Step 3: Bi-directional BLE OLED Display Sync
    final oledBytes = OledSyncService.serializeOledDisplayPacket(
      tier: riskAssessment.riskTier,
      batteryPct: batteryState.percentage,
      riskScore: riskAssessment.compositeScore,
      isSosActive: _sosManager.state == SosState.countdown15s || _sosManager.state == SosState.escalatedToDispatch,
    );
    bleService.writeOledSyncPayload(oledBytes);

    currentState = ProcessedDashboardState(
      raw: raw,
      cleanPpgIr: ppgResult.cleanIr,
      heartRate: ppgResult.estimatedHr,
      rmssd: ppgResult.rmssd,
      spO2: ppgResult.estimatedSpO2,
      cardiacAnomaly: cardiacResult,
      fallState: fallState,
      heatIndexC: heatIndexC,
      heatBand: heatBand,
      skinThermal: skinThermal,
      batteryState: batteryState,
      riskAssessment: riskAssessment,
      sosState: _sosManager.state,
      sosCountdownSeconds: _sosManager.remainingSeconds,
      ppgWaveformHistory: List.from(_ppgBuffer),
    );

    notifyListeners();
  }

  void triggerManualSos() {
    _sosManager.startEscalation(reason: 'MANUAL APP SOS OVERRIDE', isManualPanic: true);
    notifyListeners();
  }

  void dismissSos() {
    _sosManager.dismissByWearer();
    _fallEngine.reset();
    notifyListeners();
  }

  void resetSos() {
    _sosManager.reset();
    _fallEngine.reset();
    notifyListeners();
  }

  void selectScenario(SimulationScenario scenario) {
    resetSos();
    bleService.switchScenario(scenario);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _sosManager.dispose();
    super.dispose();
  }
}
