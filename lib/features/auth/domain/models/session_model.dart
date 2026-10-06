class SessionModel {
  final String id;
  final String userId;
  final String tokenHash;
  final DateTime expiresAt;
  final DateTime createdAt;
  final bool revoked;

  const SessionModel({
    required this.id,
    required this.userId,
    required this.tokenHash,
    required this.expiresAt,
    required this.createdAt,
    required this.revoked,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    return SessionModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      tokenHash: json['token_hash'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      revoked: json['revoked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'token_hash': tokenHash,
      'expires_at': expiresAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'revoked': revoked,
    };
  }

  bool get isValid => !revoked && DateTime.now().toUtc().isBefore(expiresAt.toUtc());
}
