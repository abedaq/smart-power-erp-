class LicenseModel {
  final String id;
  final String clientName;
  final String? stationCode;
  final String licenseKey;
  final String? boundHwid;
  final DateTime startsAt;
  final DateTime expiresAt;
  final bool isActive;
  final int maxOfflineDays;
  final DateTime? lastHeartbeatAt;
  final String? lastKnownIp;
  final String? appVersion;
  final String? emergencyOfflineCode;
  final DateTime? emergencyOfflineCodeExpiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  LicenseModel({
    required this.id,
    required this.clientName,
    this.stationCode,
    required this.licenseKey,
    this.boundHwid,
    required this.startsAt,
    required this.expiresAt,
    required this.isActive,
    required this.maxOfflineDays,
    this.lastHeartbeatAt,
    this.lastKnownIp,
    this.appVersion,
    this.emergencyOfflineCode,
    this.emergencyOfflineCodeExpiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LicenseModel.fromJson(Map<String, dynamic> json) {
    return LicenseModel(
      id: json['id'] as String,
      clientName: json['client_name'] as String? ?? 'بدون اسم',
      stationCode: json['station_code'] as String?,
      licenseKey: json['license_key'] as String? ?? '',
      boundHwid: json['bound_hwid'] as String?,
      startsAt: json['starts_at'] != null
          ? DateTime.parse(json['starts_at'] as String)
          : DateTime.now(),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : DateTime.now().add(const Duration(days: 30)),
      isActive: json['is_active'] as bool? ?? true,
      maxOfflineDays: (json['max_offline_days'] as num?)?.toInt() ?? 14,
      lastHeartbeatAt: json['last_heartbeat_at'] != null
          ? DateTime.parse(json['last_heartbeat_at'] as String)
          : null,
      lastKnownIp: json['last_known_ip'] as String?,
      appVersion: json['app_version'] as String?,
      emergencyOfflineCode: json['emergency_offline_code'] as String?,
      emergencyOfflineCodeExpiresAt:
          json['emergency_offline_code_expires_at'] != null
              ? DateTime.parse(
                  json['emergency_offline_code_expires_at'] as String)
              : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'client_name': clientName,
      'station_code': stationCode,
      'license_key': licenseKey,
      'bound_hwid': boundHwid,
      'starts_at': startsAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'is_active': isActive,
      'max_offline_days': maxOfflineDays,
      'last_heartbeat_at': lastHeartbeatAt?.toIso8601String(),
      'last_known_ip': lastKnownIp,
      'app_version': appVersion,
      'emergency_offline_code': emergencyOfflineCode,
      'emergency_offline_code_expires_at':
          emergencyOfflineCodeExpiresAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isBound => boundHwid != null && boundHwid!.isNotEmpty;
  int get daysRemaining => expiresAt.difference(DateTime.now()).inDays;
}
