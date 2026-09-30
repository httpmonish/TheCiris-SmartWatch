import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../services/storage_service.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = StorageService();
    final history = storage.getHistory();

    final demoEvents = [
      {"time": "11:32 AM", "event": "Nominal Health Baseline Recorded", "risk": "0.12", "tier": "NOMINAL"},
      {"time": "10:15 AM", "event": "Elevated Ambient Heat Index (42.5°C)", "risk": "0.58", "tier": "WARNING"},
      {"time": "09:40 AM", "event": "Simulated Fall Test Cleared by Wearer", "risk": "0.85", "tier": "DISMISSED"},
      {"time": "08:10 AM", "event": "BLE Device Connected (ESP32)", "risk": "0.00", "tier": "SYSTEM"},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('INCIDENT & RISK LOGS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'RECENT TELEMETRY SESSIONS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          ...demoEvents.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: e["tier"] == "WARNING"
                        ? AppColors.warningOrange.withOpacity(0.15)
                        : (e["tier"] == "DISMISSED" ? AppColors.dangerRed.withOpacity(0.15) : AppColors.primary.withOpacity(0.15)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    e["tier"] == "WARNING"
                        ? Icons.warning_amber_rounded
                        : (e["tier"] == "DISMISSED" ? Icons.emergency_rounded : Icons.info_outline_rounded),
                    color: e["tier"] == "WARNING"
                        ? AppColors.warningOrange
                        : (e["tier"] == "DISMISSED" ? AppColors.dangerRed : AppColors.primary),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e["event"]!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(height: 3),
                      Text("Timestamp: ${e["time"]} • Risk Score: ${e["risk"]}", style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
