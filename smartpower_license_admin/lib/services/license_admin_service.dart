import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/license_model.dart';

class LicenseAdminService {
  final SupabaseClient _client = Supabase.instance.client;

  // 1. Fetch All Licenses
  Future<List<LicenseModel>> fetchLicenses() async {
    final response = await _client
        .from('licenses')
        .select()
        .order('created_at', ascending: false);

    return (response as List)
        .map((e) => LicenseModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // 2. Generate a Unique Key in SP-2026-XXXX-XXXX format
  String generateLicenseKey() {
    final random = Random();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Clean alphanumeric
    String part1 = List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
    String part2 = List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
    return 'SP-2026-$part1-$part2';
  }

  // 3. Generate Emergency Offline Code in EMG-XXXX-XXXX-XXXX format
  String generateEmergencyCode() {
    final random = Random();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    String p1 = List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
    String p2 = List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
    String p3 = List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
    return 'EMG-$p1-$p2-$p3';
  }

  // 4. Create New License
  Future<LicenseModel> createLicense({
    required String clientName,
    required int durationDays,
    required int maxOfflineDays,
  }) async {
    final key = generateLicenseKey();
    final now = DateTime.now();
    final expiresAt = now.add(Duration(days: durationDays));

    final data = {
      'client_name': clientName.trim(),
      'license_key': key,
      'bound_hwid': null,
      'starts_at': now.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'is_active': true,
      'max_offline_days': maxOfflineDays,
    };

    final response = await _client.from('licenses').insert(data).select().single();
    return LicenseModel.fromJson(response);
  }

  // 5. Unbind HWID (Allows device transfer / replacement)
  Future<void> unbindHWID(String licenseId) async {
    await _client.from('licenses').update({
      'bound_hwid': null,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', licenseId);
  }

  // 6. Toggle Active / Suspended status
  Future<void> toggleActiveStatus(String licenseId, bool isActive) async {
    await _client.from('licenses').update({
      'is_active': isActive,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', licenseId);
  }

  // 7. Extend Subscription
  Future<void> extendSubscription(String licenseId, DateTime currentExpiry, int additionalDays) async {
    DateTime baseDate = currentExpiry.isAfter(DateTime.now()) ? currentExpiry : DateTime.now();
    final newExpiry = baseDate.add(Duration(days: additionalDays));

    await _client.from('licenses').update({
      'expires_at': newExpiry.toIso8601String(),
      'is_active': true,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', licenseId);
  }

  // 8. Generate and Assign Emergency Offline Code (Valid for 15 days)
  Future<String> assignEmergencyCode(String licenseId) async {
    final code = generateEmergencyCode();
    final expiresAt = DateTime.now().add(const Duration(days: 15));

    await _client.from('licenses').update({
      'emergency_offline_code': code,
      'emergency_offline_code_expires_at': expiresAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', licenseId);

    return code;
  }

  // 9. Delete License
  Future<void> deleteLicense(String licenseId) async {
    await _client.from('licenses').delete().eq('id', licenseId);
  }
}
