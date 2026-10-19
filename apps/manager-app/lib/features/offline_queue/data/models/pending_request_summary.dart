import 'dart:convert';

import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/emergency/data/models/emergency_type.dart';

/// 큐 화면(`offline_queue_screen.dart`)이 보여줄 대기 요청 한 건 — drift
/// 가 생성한 행 타입(`PendingRequest`)을 그대로 노출하지 않고 옮겨,
/// presentation 이 drift 를 직접 import 하지 않게 한다(CONVENTIONS_FLUTTER.md
/// §2 "presentation 이 data 구현 세부를 모른다").
class PendingRequestSummary {
  const new({
    required this.id,
    required this.endpoint,
    required this.method,
    required this.payload,
    required this.createdAt,
    this.failed = false,
  });

  final int id;
  final String endpoint;
  final String method;

  /// 요청 본문(JSON 문자열) — 무슨 처리인지 사람이 읽는 이름을 만드는 데 쓴다.
  final String payload;
  final DateTime createdAt;

  /// 서버가 5xx 를 되풀이해 재생에서 뺀 **영구 실패 행**이다. 큐 화면에는 남아 사용자가 직접 지운다 —
  /// 명단 행의 "전송 대기" 표시 대상이 아니다(다시 눌러 새로 보낼 수 있다).
  final bool failed;

  /// 비상 신고 요청(`POST /runs/{runId}/emergency`)의 경로인가 — 큐 재생이 영구 실패 상한에서 빼는 대상이고(Ruling 616),
  /// 비상 화면이 "전송 실패 — 계속 다시 보내는 중" 을 보일 근거다.
  static bool isEmergencyEndpoint(String endpoint) =>
      endpoint.endsWith('/emergency');

  /// 승하차지 도착 처리(`POST /runs/{runId}/stops/{stopId}/arrive`)의 경로인가(859) — 재전송이 `DUPLICATE_ARRIVE`
  /// 를 성공으로 흡수하는 대상이다.
  static bool isArriveEndpoint(String endpoint) =>
      endpoint.contains('/stops/') && endpoint.endsWith('/arrive');

  /// 이 요청이 도착 처리인가 — [isArriveEndpoint].
  bool get isArrive => isArriveEndpoint(endpoint);

  /// 도착 처리면 그 승하차지 id, 아니면 `null` — 운행 화면이 "도착 처리 저장됨" 인 곳을 가르는 근거다(859).
  String? get arriveStopId {
    if (!isArrive) return null;
    return endpoint.split('/stops/').last.split('/').first;
  }

  /// 이 요청이 비상 신고인가 — [isEmergencyEndpoint].
  bool get isEmergency => isEmergencyEndpoint(endpoint);

  /// 예외 보고(`POST /runs/{runId}/reports`)의 경로인가(Ruling 894 ⑧) — 통신 두절 때 승하차와 같은 대기열에 쌓인다.
  static bool isReportEndpoint(String endpoint) =>
      endpoint.endsWith('/reports');

  /// 미승차 연락 기록(`POST /runs/{runId}/riders/{riderId}/no-show-contacts`)의 경로인가(Ruling 894 ⑧).
  static bool isNoShowContactEndpoint(String endpoint) =>
      endpoint.endsWith('/no-show-contacts');

  /// 이 요청이 예외 보고인가 — [isReportEndpoint].
  bool get isReport => isReportEndpoint(endpoint);

  /// 이 요청이 미승차 연락 기록인가 — [isNoShowContactEndpoint].
  bool get isNoShowContact => isNoShowContactEndpoint(endpoint);

  /// 승하차 처리(`/runs/{runId}/riders/{riderId}`)면 그 학생의 rider id, 아니면 `null` — 명단 행이 "전송 대기"
  /// 로 바뀌는 근거다. 같은 학생 경로 아래의 연락 기록은 상태 처리가 아니라 행을 "전송 대기" 로 바꾸지 않는다.
  String? get riderId {
    if (!endpoint.contains('/riders/') || isNoShowContact) return null;
    return endpoint.split('/riders/').last.split('/').first;
  }

  /// 사람이 알아볼 수 있는 이름 — `PATCH /runs/…/riders/…` 같은 내부 표기를 화면에 내지 않는다.
  String get description {
    final body = _decodeBody();
    if (isEmergency) {
      final type = EmergencyType.fromWireValueOrNull(body['type'] as String?);
      return type == null ? '비상 신고' : '비상 신고 · ${type.label}';
    }
    if (isArrive) return '승하차지 도착 처리';
    if (isNoShowContact) return '미승차 연락 기록';
    if (isReport) {
      return body['type'] == 'guardian_absent' ? '보호자 부재 보고' : '현장 상황 보고';
    }
    if (endpoint.contains('/riders/')) {
      return switch (RiderStatus.fromWireValueOrNull(
        body['status'] as String?,
      )) {
        RiderStatus.boarded => '탑승 처리',
        RiderStatus.alighted => '하차 처리',
        RiderStatus.noShow => '미승차 처리',
        _ => '승하차 처리',
      };
    }
    return '전송 대기 요청';
  }

  /// 이 처리를 기록한 시각 — 본문의 `occurred_at`(오프라인에서 누른 실제 시각)이 있으면 그것, 없으면 큐에 쌓인 시각.
  /// 학생 이름을 명단에서 못 찾을 때 어느 처리인지 알아보는 단서로 쓴다.
  DateTime get recordedAt {
    final raw = _decodeBody()['occurred_at'];
    final parsed = raw is String ? DateTime.tryParse(raw) : null;
    return (parsed ?? createdAt).toLocal();
  }

  Map<String, dynamic> _decodeBody() {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }
}

/// 재생 중 서버가 확정 거절(4xx)해 큐에서 지운 요청 한 건 — 무엇이 지워졌는지(요청) · 왜 거절됐는지(상태 · 코드 ·
/// 서버 문구)를 사용자에게 남기는 근거다(Ruling 882).
class DroppedRequest {
  const new({
    required this.request,
    required this.statusCode,
    required this.code,
    required this.message,
  });

  /// 지워진 요청.
  final PendingRequestSummary request;

  /// 서버가 돌려준 HTTP 상태(4xx).
  final int statusCode;

  /// 서버 에러 코드 — 본문이 JSON 이 아니면 빈 문자열.
  final String code;

  /// 서버 에러 문구 — 본문이 JSON 이 아니면 빈 문자열.
  final String message;
}

/// `OfflineQueueRepository.replayPending` 결과 — 큐 화면이 "N건 처리, M건
/// 대기 중" 같은 안내에 쓴다.
class ReplayResult {
  const new({
    required this.succeeded,
    required this.stillPending,
    required this.droppedPermanently,
    this.failedPermanently = 0,
    this.dropped = const [],
  });

  /// 재전송이 2xx 로 끝나 큐에서 빠진 건수.
  final int succeeded;

  /// 여전히 네트워크 장애라 큐에 남은 건수.
  final int stillPending;

  /// 서버가 4xx 로 확정 거부해 재시도해도 성공할 수 없어 큐에서 뺀 건수
  /// (예: 그사이 회차가 종료돼 `RUN_NOT_MOVING` 등으로 굳어진 요청).
  final int droppedPermanently;

  /// 서버가 5xx 를 시도·나이 상한까지 되풀이해 이번 재생에서 영구 실패로 뺀 건수 — 행은 큐 화면에 남는다.
  final int failedPermanently;

  /// [droppedPermanently] 로 센 요청의 내용 — 건수만으로는 무엇이 지워졌는지 알 수 없다(Ruling 882).
  final List<DroppedRequest> dropped;
}
