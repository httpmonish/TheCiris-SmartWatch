import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/constants.dart';
import '../models/sensor_reading.dart';
import '../models/risk_result.dart';
import '../services/ble_service.dart';
import '../services/motion_service.dart';
import '../services/ml_service.dart';
import '../services/heat_index_service.dart';
import '../services/risk_engine.dart';
import '../services/alert_service.dart';
import '../widgets/risk_banner.dart';
import '../widgets/vitals_card.dart';
import '../core/ble/ble_mock_simulator.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  final BleService _ble = BleService();
  final MotionService _motion = MotionService();
  final AlertService _alert = AlertService();

  SensorReading? _currentReading;
  RiskResult? _currentRisk;
  final List<double> _waveform = [];

  int _sosCountdown = 15;
  bool _isSosActive = false;

  @override
  void initState() {
    super.initState();
    _ble.readingStream.listen((reading) {
      if (!mounted) return;

      // 1. Process Motion
      final motionPhase = _motion.processMotionFrame(
        ax: reading.accelX,
        ay: reading.accelY,
        az: reading.accelZ,
        pressureHpa: reading.pressureHpa,
        timestampMs: reading.timestampMs,
      );

      // 2. Process ML Inference
      final jerk = reading.accelX.abs() + reading.accelY.abs() + (reading.accelZ - 9.81).abs();
      final mlResult = MLService.predictAnomaly(
        heartRate: reading.heartRate,
        rmssd: reading.rmssd,
        spO2: reading.spO2,
        skinTemp: reading.skinTempC,
        ambientTemp: reading.ambientTempC,
        imuJerk: jerk,
      );

      // 3. Compute Heat Index
      final heatIndex = HeatIndexService.computeHeatIndex(
        reading.ambientTempC,
        reading.ambientHumidity,
      );

      // 4. Compute Fused Risk
      final risk = RiskEngine.computeRisk(
        reading: reading,
        motionPhase: motionPhase,
        mlResult: mlResult,
        heatIndexC: heatIndex,
      );

      // Waveform update
      _waveform.add((reading.ppgIr % 1000).toDouble() - 500);
      if (_waveform.length > 60) _waveform.removeAt(0);

      // SOS Trigger logic
      if (risk.requiresEmergencyEscalation && !_isSosActive) {
        _startSosCountdown(risk.primaryReason);
      }

      setState(() {
        _currentReading = reading;
        _currentRisk = risk;
      });
    });
  }

  void _startSosCountdown(String reason) {
    _isSosActive = true;
    _sosCountdown = 15;
    _alert.triggerEscalationChain(emergencyReason: reason, lat: 37.7749, lng: -122.4194);
  }

  void _dismissSos() {
    setState(() {
      _isSosActive = false;
      _motion.reset();
      _alert.resetAlert();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentReading == null || _currentRisk == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final reading = _currentReading!;
    final risk = _currentRisk!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AEGIS GUARDIAN'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: reading.solarCharging ? const Color(0xFF065F46) : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: reading.solarCharging ? AppColors.accentGreen : AppColors.surfaceBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  reading.solarCharging ? Icons.solar_power_rounded : Icons.battery_std_rounded,
                  color: reading.solarCharging ? AppColors.accentGreen : AppColors.primary,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  '${reading.batteryPercentage}%',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildScenarioChips(),
                const SizedBox(height: 12),
                RiskBanner(riskResult: risk),
                const SizedBox(height: 14),
                _buildWaveformSection(),
                const SizedBox(height: 14),
                _buildVitalsGrid(reading),
                const SizedBox(height: 14),
                _buildEnvironmentalGrid(reading),
                const SizedBox(height: 80),
              ],
            ),
          ),
          if (_isSosActive) _buildSosOverlay(risk),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFF0F172A),
        child: ElevatedButton.icon(
          onPressed: () => _startSosCountdown("MANUAL USER SOS OVERRIDE"),
          icon: const Icon(Icons.emergency_rounded, color: Colors.white, size: 20),
          label: const Text('TRIGGER EMERGENCY SOS', style: TextStyle(fontWeight: FontWeight.w800)),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerRed),
        ),
      ),
    );
  }

  Widget _buildScenarioChips() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TEST SCENARIO INJECTION (MOCK BLE)',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip('Nominal', SimulationScenario.normalResting),
              _chip('Tachycardia Spike', SimulationScenario.cardiacAnomalyTachycardia),
              _chip('Hypoxia <90%', SimulationScenario.hypoxiaEvent),
              _chip('Heat Stress', SimulationScenario.heatStressExtreme),
              _chip('Fall Impact', SimulationScenario.fallImpactEvent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, SimulationScenario scenario) {
    return InkWell(
      onTap: () {
        _dismissSos();
        _ble.setSimulationScenario(scenario);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceBorder,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70)),
      ),
    );
  }

  Widget _buildWaveformSection() {
    final spots = <FlSpot>[];
    for (int i = 0; i < _waveform.length; i++) {
      spots.add(FlSpot(i.toDouble(), _waveform[i]));
    }

    return Container(
      height: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LIVE PPG PULSE STREAM (Shin & Cho 2019 NLMS Filtered)',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
              ),
              Text('50 Hz', style: TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVitalsGrid(SensorReading r) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: [
        VitalsCard(
          title: 'HEART RATE',
          value: '${r.heartRate.round()}',
          unit: 'BPM',
          icon: Icons.favorite_rounded,
          accentColor: r.heartRate > 120 ? AppColors.dangerRed : AppColors.primary,
        ),
        VitalsCard(
          title: 'SPO2',
          value: '${r.spO2.toStringAsFixed(1)}',
          unit: '%',
          icon: Icons.water_drop_rounded,
          accentColor: r.spO2 < 92 ? AppColors.dangerRed : AppColors.accentGreen,
        ),
        VitalsCard(
          title: 'RMSSD (HRV)',
          value: '${r.rmssd.round()}',
          unit: 'ms',
          icon: Icons.graphic_eq_rounded,
          accentColor: AppColors.purple,
        ),
      ],
    );
  }

  Widget _buildEnvironmentalGrid(SensorReading r) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: [
        VitalsCard(
          title: 'SKIN TEMP',
          value: r.skinTempC.toStringAsFixed(1),
          unit: '°C',
          icon: Icons.thermostat_rounded,
          accentColor: r.skinTempC > 38.0 ? AppColors.dangerRed : AppColors.warningYellow,
        ),
        VitalsCard(
          title: 'AMB TEMP',
          value: r.ambientTempC.toStringAsFixed(1),
          unit: '°C',
          icon: Icons.wb_sunny_rounded,
          accentColor: AppColors.warningOrange,
        ),
        VitalsCard(
          title: 'PRESSURE',
          value: r.pressureHpa.toStringAsFixed(1),
          unit: 'hPa',
          icon: Icons.speed_rounded,
          accentColor: const Color(0xFF06B6D4),
        ),
      ],
    );
  }

  Widget _buildSosOverlay(RiskResult risk) {
    return Container(
      color: Colors.black.withOpacity(0.85),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1B4B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.dangerRed, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emergency_rounded, size: 48, color: AppColors.dangerRed),
            const SizedBox(height: 10),
            const Text(
              'EMERGENCY ESCALATION ACTIVE',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              risk.primaryReason,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _dismissSos,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.surfaceBorder),
              child: const Text("I'M OK (CANCEL)", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
