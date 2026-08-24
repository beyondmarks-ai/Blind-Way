enum UserRole { blindUser, emergencyContact }

enum RiskLevel { clear, caution, danger, unknown }

enum AlertStatus { pending, active, acknowledged, resolved, cancelled }

class UserSession {
  const UserSession({
    required this.subject,
    required this.displayName,
    required this.accessToken,
    required this.role,
  });

  final String subject;
  final String displayName;
  final String accessToken;
  final UserRole role;
}

class SceneCue {
  const SceneCue({
    required this.cue,
    required this.risk,
    required this.confidence,
    this.details = '',
  });

  final String cue;
  final RiskLevel risk;
  final double confidence;
  final String details;

  factory SceneCue.fromJson(Map<String, dynamic> json) {
    final risk = RiskLevel.values.where(
      (value) => value.name == '${json['risk']}'.toLowerCase(),
    );
    return SceneCue(
      cue: (json['cue'] as String?)?.trim().isNotEmpty == true
          ? (json['cue'] as String).trim()
          : 'Vision unavailable',
      risk: risk.isEmpty ? RiskLevel.unknown : risk.first,
      confidence: ((json['confidence'] as num?)?.toDouble() ?? 0).clamp(0, 1),
      details: (json['details'] as String?)?.trim().isNotEmpty == true
          ? (json['details'] as String).trim()
          : (json['cue'] as String?)?.trim() ?? 'Vision unavailable',
    );
  }
}

class EmergencyAlert {
  const EmergencyAlert({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.blindUserName,
    required this.triggerSource,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.acknowledgedBy,
    this.lastCue,
    this.lastDetails,
    this.lastRisk,
    this.lastConfidence,
    this.snapshotCapturedAt,
    this.snapshotAvailable = false,
    this.locationUpdatedAt,
  });

  final String id;
  final AlertStatus status;
  final DateTime startedAt;
  final String blindUserName;
  final String triggerSource;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final String? acknowledgedBy;
  final String? lastCue;
  final String? lastDetails;
  final RiskLevel? lastRisk;
  final double? lastConfidence;
  final DateTime? snapshotCapturedAt;
  final bool snapshotAvailable;
  final DateTime? locationUpdatedAt;

  factory EmergencyAlert.fromJson(Map<String, dynamic> json) => EmergencyAlert(
    id: json['id'] as String,
    status: AlertStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => AlertStatus.active,
    ),
    startedAt: DateTime.tryParse('${json['startedAt']}') ?? DateTime.now(),
    blindUserName: json['blindUserName'] as String? ?? 'Blind Way user',
    triggerSource: json['triggerSource'] as String? ?? 'button',
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    accuracy: (json['accuracy'] as num?)?.toDouble(),
    acknowledgedBy: json['acknowledgedBy'] as String?,
    lastCue: json['lastCue'] as String?,
    lastDetails: json['lastDetails'] as String?,
    lastRisk: RiskLevel.values
        .where((value) => value.name == json['lastRisk'])
        .firstOrNull,
    lastConfidence: (json['lastConfidence'] as num?)?.toDouble(),
    snapshotCapturedAt: DateTime.tryParse(
      '${json['snapshotCapturedAt'] ?? ''}',
    ),
    snapshotAvailable: json['snapshotAvailable'] as bool? ?? false,
    locationUpdatedAt: DateTime.tryParse('${json['locationUpdatedAt'] ?? ''}'),
  );
}

class TrustedContact {
  const TrustedContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.verified,
  });

  final String id;
  final String name;
  final String phone;
  final bool verified;

  factory TrustedContact.fromJson(Map<String, dynamic> json) => TrustedContact(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Trusted contact',
    phone: json['phone'] as String? ?? '',
    verified: json['verified'] as bool? ?? false,
  );
}
