import 'dart:convert';

import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/emergency/data/models/emergency_type.dart';

/// 큐 화면(`offline_queue_screen.dart`)이 보여줄 대기 요청 한 건 — drift
/// 가 생성한 행 타입(`PendingRequest`)을 그대로 노출하지 않고 옮겨,
/// presentation 이 drift 를 직접 import 하지 않게 한다(CONVENTIONS_FLUTTER.md
/// §2 "presentation 이 data 구현 세부를 모른다").
class PendingRequestSummary {
  const PendingRequestSummary({
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

  /// 서버가 5xx 를 되풀이해 재생에서 뺀 **영구 실패 행**이다(R46-FIXRT). 큐 화면에는 남아 사용자가 직접 지운다 —
  /// 명단 행의 "전송 대기" 표시 대상이 아니다(다시 눌러 새로 보낼 수 있다).
  final bool failed;

  /// 비상 신고 요청(`POST /runs/{runId}/emergency`)의 경로인가 — 큐 재생이 영구 실패 상한에서 빼는 대상이고(Ruling 616),
  /// 비상 화면이 "전송 실패 — 계속 다시 보내는 중" 을 보일 근거다.
  static bool isEmergencyEndpoint(String endpoint) =>
      endpoint.endsWith('/emergency');

  /// 이 요청이 비상 신고인가 — [isEmergencyEndpoint].
  bool get isEmergency => isEmergencyEndpoint(endpoint);

  /// 승하차 처리(`/runs/{runId}/riders/{riderId}`)면 그 학생의 rider id, 아니면 `null` — 명단 행이 "전송 대기"
  /// 로 바뀌는 근거다(R46).
  String? get riderId {
    if (!endpoint.contains('/riders/')) return null;
    return endpoint.split('/riders/').last.split('/').first;
  }

  /// 사람이 알아볼 수 있는 이름 — `PATCH /runs/…/riders/…` 같은 내부 표기를 화면에 내지 않는다(F06-15).
  String get description {
    final body = _decodeBody();
    if (isEmergency) {
      final type = EmergencyType.fromWireValueOrNull(body['type'] as String?);
      return type == null ? '비상 신고' : '비상 신고 · ${type.label}';
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

  Map<String, dynamic> _decodeBody() {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }
}

/// `OfflineQueueRepository.replayPending` 결과 — 큐 화면이 "N건 처리, M건
/// 대기 중" 같은 안내에 쓴다.
class ReplayResult {
  const ReplayResult({
    required this.succeeded,
    required this.stillPending,
    required this.droppedPermanently,
    this.failedPermanently = 0,
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
}
