import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EmergencyContact {
  final String name;
  final String phone;
  final String relation;

  const EmergencyContact({
    required this.name,
    required this.phone,
    required this.relation,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'relation': relation,
  };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) => EmergencyContact(
    name: json['name'] ?? '',
    phone: json['phone'] ?? '',
    relation: json['relation'] ?? '',
  );
}

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _contactsKey = "secure_emergency_contacts_v1";

  List<EmergencyContact> _contacts = [
    const EmergencyContact(name: "Dr. Sarah Chen", phone: "+15550192834", relation: "Primary Physician"),
    const EmergencyContact(name: "Central Emergency Dispatch", phone: "911", relation: "First Responder"),
  ];

  final List<Map<String, dynamic>> _historyLogs = [];

  Future<void> init() async {
    try {
      final raw = await _secureStorage.read(key: _contactsKey);
      if (raw != null) {
        final List list = jsonDecode(raw);
        _contacts = list.map((e) => EmergencyContact.fromJson(e)).toList();
      }
    } catch (_) {}
  }

  List<EmergencyContact> getContacts() => List.unmodifiable(_contacts);

  Future<void> addContact(EmergencyContact contact) async {
    _contacts.add(contact);
    await _persistContacts();
  }

  Future<void> removeContact(int index) async {
    if (index >= 0 && index < _contacts.length) {
      _contacts.removeAt(index);
      await _persistContacts();
    }
  }

  Future<void> _persistContacts() async {
    final encoded = jsonEncode(_contacts.map((c) => c.toJson()).toList());
    await _secureStorage.write(key: _contactsKey, value: encoded);
  }

  void saveTelemetrySnapshot(Map<String, dynamic> snapshot) {
    _historyLogs.insert(0, {
      'timestamp': DateTime.now().toIso8601String(),
      ...snapshot,
    });
    if (_historyLogs.length > 200) {
      _historyLogs.removeLast();
    }
  }

  List<Map<String, dynamic>> getHistory() => List.unmodifiable(_historyLogs);
}
