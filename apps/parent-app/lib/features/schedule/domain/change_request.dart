/// `POST`·`GET /students/{id}/change-requests` 모델 (API_SPEC §3.8·§3.9).
enum ChangeRequestType {
  relocate,
  cancel;

  static ChangeRequestType fromWireValue(String value) => switch (value) {
    'relocate' => ChangeRequestType.relocate,
    'cancel' => ChangeRequestType.cancel,
    _ => throw ArgumentError('알 수 없는 change_request type: $value'),
  };

  String get wireValue => name;
}

enum ChangeRequestStatus {
  pending,
  approved,
  rejected,
  autoRejected;

  static ChangeRequestStatus fromWireValue(String value) => switch (value) {
    'pending' => ChangeRequestStatus.pending,
    'approved' => ChangeRequestStatus.approved,
    'rejected' => ChangeRequestStatus.rejected,
    'auto_rejected' => ChangeRequestStatus.autoRejected,
    _ => throw ArgumentError('알 수 없는 change_request status: $value'),
  };
}

/// §3.9 목록 항목.
class ChangeRequest {
  const ChangeRequest({
    required this.changeRequestId,
    required this.type,
    required this.status,
    this.rejectReason,
    this.runId,
    this.requestedAt,
    this.decidedAt,
  });

  factory ChangeRequest.fromJson(Map<String, dynamic> json) => ChangeRequest(
    changeRequestId: json['change_request_id'] as String,
    type: ChangeRequestType.fromWireValue(json['type'] as String),
    status: ChangeRequestStatus.fromWireValue(json['status'] as String),
    rejectReason: json['reject_reason'] as String?,
    runId: json['run_id'] as String?,
    requestedAt: json['requested_at'] == null
        ? null
        : DateTime.parse(json['requested_at'] as String),
    decidedAt: json['decided_at'] == null
        ? null
        : DateTime.parse(json['decided_at'] as String),
  );

  final String changeRequestId;
  final ChangeRequestType type;
  final ChangeRequestStatus status;

  /// `rejected` 일 때만 존재.
  final String? rejectReason;
  final String? runId;
  final DateTime? requestedAt;
  final DateTime? decidedAt;
}

/// §3.9 응답 봉투 — 홈 배지용 `pending_count` 를 함께 담는다.
class ChangeRequestPage {
  const ChangeRequestPage({required this.items, required this.pendingCount});

  factory ChangeRequestPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'] as List<dynamic>? ?? [];
    return ChangeRequestPage(
      items: items
          .cast<Map<String, dynamic>>()
          .map(ChangeRequest.fromJson)
          .toList(),
      pendingCount: json['pending_count'] as int,
    );
  }

  final List<ChangeRequest> items;
  final int pendingCount;
}

/// §3.8 생성 응답(`201`).
class ChangeRequestCreateResult {
  const ChangeRequestCreateResult({
    required this.changeRequestId,
    required this.status,
    required this.result,
    this.deadlineAt,
  });

  factory ChangeRequestCreateResult.fromJson(Map<String, dynamic> json) =>
      ChangeRequestCreateResult(
        changeRequestId: json['change_request_id'] as String,
        status: ChangeRequestStatus.fromWireValue(json['status'] as String),
        result: json['result'] as String,
        deadlineAt: json['deadline_at'] == null
            ? null
            : DateTime.parse(json['deadline_at'] as String),
      );

  final String changeRequestId;
  final ChangeRequestStatus status;

  /// `applied` · `pending_approval`.
  final String result;
  final DateTime? deadlineAt;
}
