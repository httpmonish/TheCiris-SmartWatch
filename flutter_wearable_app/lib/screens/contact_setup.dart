import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../services/storage_service.dart';

class ContactSetup extends StatefulWidget {
  const ContactSetup({super.key});

  @override
  State<ContactSetup> createState() => _ContactSetupState();
}

class _ContactSetupState extends State<ContactSetup> {
  final StorageService _storage = StorageService();

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final relationCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Add Emergency Contact', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Contact Name', labelStyle: TextStyle(color: AppColors.textSecondary)),
              style: const TextStyle(color: Colors.white),
            ),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone Number', labelStyle: TextStyle(color: AppColors.textSecondary)),
              style: const TextStyle(color: Colors.white),
            ),
            TextField(
              controller: relationCtrl,
              decoration: const InputDecoration(labelText: 'Relationship (e.g. Caregiver)', labelStyle: TextStyle(color: AppColors.textSecondary)),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && phoneCtrl.text.isNotEmpty) {
                _storage.addContact(EmergencyContact(
                  name: nameCtrl.text,
                  phone: phoneCtrl.text,
                  relation: relationCtrl.text,
                ));
                setState(() {});
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save Contact'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _storage.getContacts();

    return Scaffold(
      appBar: AppBar(
        title: const Text('EMERGENCY DISPATCH CHAIN'),
        actions: [
          IconButton(onPressed: _showAddDialog, icon: const Icon(Icons.person_add_rounded, color: AppColors.primary)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_rounded, color: AppColors.primary, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'When Risk Score >= 0.75 or Fall is confirmed, an automated SMS dispatch is sent to all contacts below with GPS telemetry.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(contacts.length, (idx) {
            final c = contacts[idx];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.surfaceBorder,
                  child: Text('${idx + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                title: Text(c.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Text('${c.relation} • ${c.phone}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.dangerRed, size: 20),
                  onPressed: () {
                    _storage.removeContact(idx);
                    setState(() {});
                  },
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
