import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';

class ReliefShelter {
  final String id;
  final String name;
  final String district;
  final double latitude;
  final double longitude;
  final int capacity;
  final String contact;
  final List<String> supplies;
  final bool isFloodSafeZone;
  final double distanceKm;

  const ReliefShelter({
    required this.id,
    required this.name,
    required this.district,
    required this.latitude,
    required this.longitude,
    required this.capacity,
    required this.contact,
    required this.supplies,
    required this.isFloodSafeZone,
    this.distanceKm = 0.0,
  });

  ReliefShelter copyWithDistance(double dist) => ReliefShelter(
    id: id,
    name: name,
    district: district,
    latitude: latitude,
    longitude: longitude,
    capacity: capacity,
    contact: contact,
    supplies: supplies,
    isFloodSafeZone: isFloodSafeZone,
    distanceKm: dist,
  );

  factory ReliefShelter.fromJson(Map<String, dynamic> json, {double distance = 0.0}) {
    return ReliefShelter(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      district: json['district'] ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      capacity: json['capacity'] ?? 0,
      contact: json['contact'] ?? '',
      supplies: List<String>.from(json['supplies'] ?? []),
      isFloodSafeZone: json['isFloodSafeZone'] ?? true,
      distanceKm: distance,
    );
  }
}

class ShelterService {
  static final ShelterService _instance = ShelterService._internal();
  factory ShelterService() => _instance;
  ShelterService._internal();

  List<ReliefShelter> _cachedShelters = [];
  bool _isLoaded = false;

  /// Loads bundled offline disaster shelters from assets/data/shelters.json
  Future<void> loadShelters() async {
    if (_isLoaded) return;
    try {
      final jsonString = await rootBundle.loadString('assets/data/shelters.json');
      final List list = jsonDecode(jsonString);
      _cachedShelters = list.map((e) => ReliefShelter.fromJson(e)).toList();
      _isLoaded = true;
    } catch (_) {
      // Fallback in-memory catalog
      _cachedShelters = [
        const ReliefShelter(
          id: "SHELTER_MH_001",
          name: "Pune High School Flood Evacuation Camp",
          district: "Pune, Maharashtra",
          latitude: 18.5204,
          longitude: 73.8567,
          capacity: 500,
          contact: "+91 20 2612 3456",
          supplies: ["Clean Water", "Medical Unit", "Power Generator"],
          isFloodSafeZone: true,
        ),
      ];
      _isLoaded = true;
    }
  }

  /// Calculates great-circle distance in kilometers between two GPS coordinates using Haversine formula
  static double calculateHaversineKm(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371.0; // Earth radius in km
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);

  /// Returns sorted list of relief shelters from nearest to farthest relative to current GPS
  Future<List<ReliefShelter>> getSheltersRankedByDistance({
    required double userLat,
    required double userLng,
  }) async {
    if (!_isLoaded) await loadShelters();

    final ranked = _cachedShelters.map((s) {
      final dist = calculateHaversineKm(userLat, userLng, s.latitude, s.longitude);
      return s.copyWithDistance(dist);
    }).toList();

    ranked.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return ranked;
  }

  /// Gets the single closest emergency relief camp
  Future<ReliefShelter?> getNearestShelter(double userLat, double userLng) async {
    final list = await getSheltersRankedByDistance(userLat: userLat, userLng: userLng);
    return list.isNotEmpty ? list.first : null;
  }
}
