class DeviceRemoteFlags {
  const DeviceRemoteFlags({
    required this.deviceId,
    required this.pingRequested,
    required this.pingStatus,
    required this.forgetRequested,
    required this.forgetStatus,
    this.pingRequestedAt,
    this.pingAckAt,
    this.pingNote,
    this.forgetRequestedAt,
    this.forgetAckAt,
    this.forgetProcessedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String deviceId;
  final bool pingRequested;
  final String pingStatus;
  final DateTime? pingRequestedAt;
  final DateTime? pingAckAt;
  final String? pingNote;
  final bool forgetRequested;
  final String forgetStatus;
  final DateTime? forgetRequestedAt;
  final DateTime? forgetAckAt;
  final DateTime? forgetProcessedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory DeviceRemoteFlags.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value.toUtc();
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value)?.toUtc();
      }
      return null;
    }

    String normalizeStatus(String? value) {
      if (value == null || value.isEmpty) return 'idle';
      return value.toLowerCase();
    }

    return DeviceRemoteFlags(
      deviceId: map['device_id'] as String,
      pingRequested: (map['ping_requested'] as bool?) ?? false,
      pingStatus: normalizeStatus(map['ping_status'] as String?),
      pingRequestedAt: parseDate(map['ping_requested_at']),
      pingAckAt: parseDate(map['ping_ack_at']),
      pingNote: map['ping_note'] as String?,
      forgetRequested: (map['forget_requested'] as bool?) ?? false,
      forgetStatus: normalizeStatus(map['forget_status'] as String?),
      forgetRequestedAt: parseDate(map['forget_requested_at']),
      forgetAckAt: parseDate(map['forget_ack_at']),
      forgetProcessedAt: parseDate(map['forget_processed_at']),
      createdAt: parseDate(map['created_at']),
      updatedAt: parseDate(map['updated_at']),
    );
  }

  bool get pingPending =>
      pingRequested || pingStatus == 'pending' || pingStatus == 'idle';

  bool get pingAcked => pingStatus == 'ack';

  bool get forgetPending =>
      forgetRequested || forgetStatus == 'pending' || forgetStatus == 'idle';

  bool get forgetAcked => forgetStatus == 'ack';

  bool get forgetDone => forgetStatus == 'done';
}
