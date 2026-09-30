import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../services/shelter_service.dart';
import '../services/mesh_relay_service.dart';

class ShelterScreen extends StatefulWidget {
  const ShelterScreen({super.key});

  @override
  State<ShelterScreen> createState() => _ShelterScreenState();
}

class _ShelterScreenState extends State<ShelterScreen> {
  final ShelterService _shelterService = ShelterService();
  final MeshRelayService _meshService = MeshRelayService();
  List<ReliefShelter> _shelters = [];
  bool _isLoading = true;

  // Demo user GPS location (e.g. Pune / Maharashtra flood zone)
  final double _userLat = 18.5204;
  final double _userLng = 73.8567;

  @override
  void initState() {
    super.initState();
    _loadShelters();
  }

  Future<void> _loadShelters() async {
    final list = await _shelterService.getSheltersRankedByDistance(
      userLat: _userLat,
      userLng: _userLng,
    );
    setState(() {
      _shelters = list;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DISASTER RELIEF & MESH RELAY'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildMeshStatusBanner(),
                const SizedBox(height: 16),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'OFFLINE RELIEF SHELTERS (BUNDLED)',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.8),
                    ),
                    Text(
                      'No Internet Required',
                      style: TextStyle(fontSize: 10, color: AppColors.accentGreen, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ..._shelters.map((shelter) => _buildShelterCard(shelter)),
              ],
            ),
    );
  }

  Widget _buildMeshStatusBanner() {
    final relayedCount = _meshService.relayedPackets.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.hub_rounded, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BLE PEER DISASTER MESH ACTIVE',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    Text(
                      'Store-and-Forward Emergency Broadcast (Max 3 Hops)',
                      style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Relayed Packets via Peer Bands: $relayedCount',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accentGreen),
          ),
        ],
      ),
    );
  }

  Widget _buildShelterCard(ReliefShelter s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  s.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${s.distanceKm.toStringAsFixed(1)} km',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${s.district} • Capacity: ${s.capacity} persons',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: s.supplies.map((sup) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(sup, style: const TextStyle(fontSize: 9, color: Color(0xFFCBD5E1))),
            )).toList(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.phone_in_talk_rounded, size: 14, color: AppColors.accentGreen),
              const SizedBox(width: 4),
              Text(s.contact, style: const TextStyle(fontSize: 11, color: AppColors.accentGreen, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
