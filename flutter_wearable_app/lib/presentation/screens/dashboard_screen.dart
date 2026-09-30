import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../controllers/telemetry_provider.dart';
import '../../core/ble/ble_mock_simulator.dart';
import '../../algorithms/fusion/composite_risk_engine.dart';
import '../../algorithms/escalation/sos_escalation_manager.dart';

class DashboardScreen extends StatelessWidget {
  final TelemetryController controller;

  const DashboardScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.currentState;
        if (state == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F172A),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
            ),
          );
        }

        final isEmergency = state.sosState == SosState.countdown15s ||
            state.sosState == SosState.escalatedToDispatch;

        return Scaffold(
          backgroundColor: const Color(0xFF090D16),
          appBar: _buildAppBar(context, state),
          body: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildScenarioSelector(),
                    const SizedBox(height: 12),
                    _buildRiskScoreCard(state),
                    const SizedBox(height: 12),
                    _buildWaveformCard(state),
                    const SizedBox(height: 12),
                    _buildVitalsGrid(state),
                    const SizedBox(height: 12),
                    _buildEnvironmentalGrid(state),
                    const SizedBox(height: 12),
                    _buildDiagnosticsLog(state),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
              if (isEmergency) _buildSosOverlay(context, state),
            ],
          ),
          bottomNavigationBar: _buildBottomBar(context),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ProcessedDashboardState state) {
    return AppBar(
      backgroundColor: const Color(0xFF0F172A),
      elevation: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.watch_rounded, color: Color(0xFF38BDF8), size: 20),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AEGIS GUARDIAN IoT',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Colors.white),
              ),
              Text(
                '50Hz Multi-Sensor Fusion Telemetry',
                style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: state.batteryState.isSolarCharging ? const Color(0xFF065F46) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: state.batteryState.isSolarCharging ? const Color(0xFF10B981) : const Color(0xFF334155),
            ),
          ),
          child: Row(
            children: [
              Icon(
                state.batteryState.isSolarCharging ? Icons.solar_power_rounded : Icons.battery_charging_full_rounded,
                color: state.batteryState.isSolarCharging ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '${state.batteryState.percentage}% (${state.raw.batteryMillivolts}mV)',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScenarioSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131C2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, color: Color(0xFF38BDF8), size: 16),
              SizedBox(width: 6),
              Text(
                'TEST SIMULATION SCENARIO INJECTION',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _scenarioChip('Nominal Walk', SimulationScenario.normalResting),
              _scenarioChip('Tachycardia Spike', SimulationScenario.cardiacAnomalyTachycardia),
              _scenarioChip('Hypoxia (<90%)', SimulationScenario.hypoxiaEvent),
              _scenarioChip('Heat Stroke', SimulationScenario.heatStressExtreme),
              _scenarioChip('Fall / Impact', SimulationScenario.fallImpactEvent),
              _scenarioChip('SOS Button', SimulationScenario.panicSosPressed),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scenarioChip(String label, SimulationScenario scenario) {
    final isSelected = controller.bleService.simulator.currentScenario == scenario;
    return InkWell(
      onTap: () => controller.selectScenario(scenario),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }

  Widget _buildRiskScoreCard(ProcessedDashboardState state) {
    final score = state.riskAssessment.compositeScore;
    final tier = state.riskAssessment.riskTier;

    Color color;
    String status;
    switch (tier) {
      case RiskTier.criticalRed:
        color = const Color(0xFFEF4444);
        status = 'CRITICAL RISK / EMERGENCY';
        break;
      case RiskTier.warningOrange:
        color = const Color(0xFFF97316);
        status = 'HIGH STRAIN WARNING';
        break;
      case RiskTier.cautionYellow:
        color = const Color(0xFFFACC15);
        status = 'ELEVATED MONITORING';
        break;
      case RiskTier.nominalGreen:
        color = const Color(0xFF10B981);
        status = 'NOMINAL STATE';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131C2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(
                  value: score,
                  strokeWidth: 8,
                  backgroundColor: const Color(0xFF1E293B),
                  color: color,
                ),
              ),
              Text(
                '${(score * 100).toInt()}%',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  state.riskAssessment.primaryRiskReason,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFE2E8F0)),
                ),
                const SizedBox(height: 4),
                Text(
                  'ML Engine: ${state.cardiacAnomaly.diagnostic}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformCard(ProcessedDashboardState state) {
    final spots = <FlSpot>[];
    for (int i = 0; i < state.ppgWaveformHistory.length; i++) {
      spots.add(FlSpot(i.toDouble(), state.ppgWaveformHistory[i]));
    }

    return Container(
      height: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131C2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MAX30101 PPG PULSE WAVEFORM (Shin & Cho 2019 NLMS Filtered)',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.8),
              ),
              Text(
                '50 Hz Live',
                style: TextStyle(fontSize: 10, color: Color(0xFF38BDF8), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: spots.isEmpty
                ? const Center(child: Text('Awaiting PPG stream...', style: TextStyle(color: Colors.white54)))
                : LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      minY: -1500,
                      maxY: 1500,
                      lineBarsData: [
                        LineBarSpotData(
                          spots: spots,
                          isCurved: true,
                          color: const Color(0xFF38BDF8),
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: const Color(0xFF38BDF8).withOpacity(0.08),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildVitalsGrid(ProcessedDashboardState state) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: [
        _metricTile(
          'HEART RATE',
          '${state.heartRate.round()}',
          'BPM',
          state.heartRate > 120 ? const Color(0xFFEF4444) : const Color(0xFF38BDF8),
          Icons.favorite_rounded,
        ),
        _metricTile(
          'BLOOD OXYGEN',
          '${state.spO2.toStringAsFixed(1)}',
          '%',
          state.spO2 < 92.0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
          Icons.water_drop_rounded,
        ),
        _metricTile(
          'RMSSD (HRV)',
          '${state.rmssd.round()}',
          'ms',
          const Color(0xFFA855F7),
          Icons.graphic_eq_rounded,
        ),
      ],
    );
  }

  Widget _buildEnvironmentalGrid(ProcessedDashboardState state) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: [
        _metricTile(
          'SKIN TEMP',
          state.raw.skinTempC.toStringAsFixed(1),
          '°C',
          state.raw.skinTempC > 38.0 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
          Icons.thermostat_rounded,
        ),
        _metricTile(
          'HEAT INDEX',
          state.heatIndexC.toStringAsFixed(1),
          '°C',
          state.heatIndexC > 40.0 ? const Color(0xFFEF4444) : const Color(0xFFF97316),
          Icons.wb_sunny_rounded,
        ),
        _metricTile(
          'PRESSURE',
          state.raw.pressureHpa.toStringAsFixed(1),
          'hPa',
          const Color(0xFF06B6D4),
          Icons.speed_rounded,
        ),
      ],
    );
  }

  Widget _metricTile(String title, String value, String unit, Color accent, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF131C2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8)),
              ),
              Icon(icon, size: 14, color: accent),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: accent),
              ),
              const SizedBox(width: 3),
              Text(
                unit,
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsLog(ProcessedDashboardState state) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131C2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACTIVE FUSED TELEMETRY DIAGNOSTICS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          if (state.riskAssessment.activeAlerts.isEmpty)
            const Text(
              '✓ Zero active fault conditions. All biometrics and thermal gradients nominal.',
              style: TextStyle(fontSize: 11, color: Color(0xFF10B981)),
            )
          else
            ...state.riskAssessment.activeAlerts.map(
              (alert) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFEF4444)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        alert,
                        style: const TextStyle(fontSize: 11, color: Color(0xFFFCA5A5)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSosOverlay(BuildContext context, ProcessedDashboardState state) {
    return Container(
      color: Colors.black.withOpacity(0.85),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1B4B),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFEF4444), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emergency_rounded, size: 56, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            const Text(
              'EMERGENCY SOS TRIGGERED',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              state.riskAssessment.primaryRiskReason,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
            ),
            const SizedBox(height: 20),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  child: CircularProgressIndicator(
                    value: state.sosCountdownSeconds / 15.0,
                    strokeWidth: 8,
                    color: const Color(0xFFEF4444),
                    backgroundColor: const Color(0xFF334155),
                  ),
                ),
                Text(
                  '${state.sosCountdownSeconds}s',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => controller.dismissSos(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text("I'M OK (DISMISS)", style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => controller.triggerManualSos(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('DISPATCH NOW', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF0F172A),
      child: ElevatedButton.icon(
        onPressed: () => controller.triggerManualSos(),
        icon: const Icon(Icons.sos_rounded, color: Colors.white, size: 22),
        label: const Text('MANUAL PANIC SOS OVERRIDE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFDC2626),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
