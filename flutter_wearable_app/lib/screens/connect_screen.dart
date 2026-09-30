import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../services/ble_service.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final BleService _ble = BleService();
  bool _isScanning = false;

  void _toggleScan() async {
    setState(() {
      _isScanning = !_isScanning;
    });
    if (_isScanning) {
      await _ble.startScan();
    } else {
      await _ble.stopScan();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DEVICE CONNECTIVITY')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bluetooth_connected_rounded, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CURRENT CONNECTION',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _ble.connectedDeviceName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF065F46),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accentGreen)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('DISCOVERED BLE DEVICES (flutter_blue_plus)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              TextButton.icon(
                onPressed: _toggleScan,
                icon: Icon(_isScanning ? Icons.stop_rounded : Icons.refresh_rounded, size: 16, color: AppColors.primary),
                label: Text(_isScanning ? 'Scanning...' : 'Scan Devices', style: const TextStyle(fontSize: 12, color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_ble.scanResults.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: const Text(
                'No physical BLE devices in range. Live Synthetic 50Hz Streamer is currently active for zero-hardware testing.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            )
          else
            ..._ble.scanResults.map((result) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: ListTile(
                leading: const Icon(Icons.watch_rounded, color: AppColors.textSecondary),
                title: Text(
                  result.device.platformName.isNotEmpty ? result.device.platformName : 'Unknown Peripheral',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                subtitle: Text("${result.device.remoteId.str} • RSSI: ${result.rssi} dBm", style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                trailing: ElevatedButton(
                  onPressed: () async {
                    await _ble.connectToHardware(result.device);
                    setState(() {});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: const Text('Connect', style: TextStyle(fontSize: 11)),
                ),
              ),
            )),
        ],
      ),
    );
  }
}
