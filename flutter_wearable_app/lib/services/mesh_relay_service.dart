import 'dart:typed_data';
import 'dart:async';
import 'alert_service.dart';

class MeshRelayPacket {
  final String deviceId;
  final String eventType; // "FALL" | "CARDIAC" | "PANIC" | "MOTION_ANOMALY"
  final int timestampMs;
  final int hopCount;
  final double? latitude;
  final double? longitude;

  const MeshRelayPacket({
    required this.deviceId,
    required this.eventType,
    required this.timestampMs,
    required this.hopCount,
    this.latitude,
    this.longitude,
  });

  /// Serializes packet into compact 20-byte BLE Manufacturer Data payload for advertising
  Uint8List toBleAdvertisementPayload() {
    final buffer = Uint8List(20);
    final data = ByteData.sublistView(buffer);

    data.setUint8(0, 0xAE); // Aegis Mesh Protocol Magic Byte
    
    // Hash deviceId to 32-bit integer
    final idHash = deviceId.hashCode & 0xFFFFFFFF;
    data.setUint32(1, idHash, Endian.little);

    // Event type code
    int eventCode = switch (eventType) {
      "FALL" => 0,
      "CARDIAC" => 1,
      "PANIC" => 2,
      _ => 3,
    };
    data.setUint8(5, eventCode);
    data.setUint8(6, hopCount.clamp(0, 5));
    data.setUint32(7, (timestampMs ~/ 1000) & 0xFFFFFFFF, Endian.little);

    // Encoded GPS (int32 * 1e5)
    final latEnc = ((latitude ?? 0.0) * 100000).toInt();
    final lngEnc = ((longitude ?? 0.0) * 100000).toInt();
    data.setInt32(11, latEnc, Endian.little);
    data.setInt32(15, lngEnc, Endian.little);

    return buffer;
  }

  /// Parses 20-byte BLE Manufacturer Data packet received from a peer device's BLE advertisement
  static MeshRelayPacket? fromBleAdvertisementPayload(Uint8List bytes) {
    if (bytes.length < 20 || bytes[0] != 0xAE) return null;

    final data = ByteData.sublistView(bytes);
    final idHash = data.getUint32(1, Endian.little);
    final eventCode = data.getUint8(5);
    final hop = data.getUint8(6);
    final timestamp = data.getUint32(7, Endian.little) * 1000;
    final lat = data.getInt32(11, Endian.little) / 100000.0;
    final lng = data.getInt32(15, Endian.little) / 100000.0;

    final eventType = switch (eventCode) {
      0 => "FALL",
      1 => "CARDIAC",
      2 => "PANIC",
      _ => "MOTION_ANOMALY",
    };

    return MeshRelayPacket(
      deviceId: "AEGIS-PEER-${idHash.toRadixString(16).toUpperCase()}",
      eventType: eventType,
      timestampMs: timestamp,
      hopCount: hop,
      latitude: lat != 0.0 ? lat : null,
      longitude: lng != 0.0 ? lng : null,
    );
  }
}

class MeshRelayService {
  static final MeshRelayService _instance = MeshRelayService._internal();
  factory MeshRelayService() => _instance;
  MeshRelayService._internal();

  final AlertService _alertService = AlertService();
  static const int maxHops = 3;

  final Set<String> _seenPacketSignatures = {};
  final List<MeshRelayPacket> relayedPackets = [];

  /// Ingests a raw BLE advertisement payload discovered by scanning
  Future<bool> processReceivedAdvertisement(Uint8List manufacturerData) async {
    final packet = MeshRelayPacket.fromBleAdvertisementPayload(manufacturerData);
    if (packet == null) return false;

    // Deduplication check: (deviceId + eventType + timestamp)
    final signature = "${packet.deviceId}_${packet.eventType}_${packet.timestampMs}";
    if (_seenPacketSignatures.contains(signature)) {
      return false; // Already processed
    }
    _seenPacketSignatures.add(signature);
    relayedPackets.insert(0, packet);

    // If packet has not exceeded max hops:
    if (packet.hopCount < maxHops) {
      // 1. Gateway Forward: Relay out to emergency dispatch with Peer Mesh Tag
      final dispatchReason = "RELAYED_VIA_PEER_MESH (Hop ${packet.hopCount + 1}): Peer ${packet.deviceId} triggered ${packet.eventType}";
      await _alertService.triggerEscalationChain(
        emergencyReason: dispatchReason,
        lat: packet.latitude ?? 0.0,
        lng: packet.longitude ?? 0.0,
      );

      // 2. Re-broadcast over BLE Advertisement with incremented hop_count
      final nextPacket = MeshRelayPacket(
        deviceId: packet.deviceId,
        eventType: packet.eventType,
        timestampMs: packet.timestampMs,
        hopCount: packet.hopCount + 1,
        latitude: packet.latitude,
        longitude: packet.longitude,
      );
      _rebroadcastBleMeshPacket(nextPacket.toBleAdvertisementPayload());
      return true;
    }

    return false;
  }

  void _rebroadcastBleMeshPacket(Uint8List payload) {
    // In production: ESP32 or mobile peripheral starts BLE advertisement with manufacturer data
  }
}
