import 'package:flutter/foundation.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/roster/domain/models/roster_response.dart';

/// 명단 화면이 하위 위젯에 넘기는 조작 상태와 처리 콜백 묶음.
///
/// 처리 중인 학생 · 펼친 승하차지 · 오류 안내는 화면(State)이 쥐고, 하위 위젯은 이 묶음으로 읽기만 한다.
class RosterInteraction {
  const new({
    required this.readOnly,
    required this.pendingRiderIds,
    required this.expandedStopIds,
    required this.pastExpanded,
    required this.errorMessage,
    required this.onToggleStop,
    required this.onTogglePast,
    required this.onCall,
    required this.onUpdateStatus,
    required this.onConfirmNoShow,
    required this.onConfirmRevert,
    required this.onOpenNoShow,
  });

  /// 기사의 조회 전용 열람 — 처리 단추 · 지연 알림 · 대기열이 없다.
  final bool readOnly;

  /// 응답을 기다리는 학생들.
  final Set<String> pendingRiderIds;

  /// 사용자가 직접 펼친 승하차지.
  final Set<String> expandedStopIds;

  /// 지난 곳 묶음을 펼쳤는가.
  final bool pastExpanded;
  final String? errorMessage;
  final void Function(String stopId) onToggleStop;
  final VoidCallback onTogglePast;
  final void Function(String runId, String riderId) onCall;
  final void Function(String runId, String riderId, RiderStatus status)
  onUpdateStatus;
  final void Function(String runId, String riderId, String name)
  onConfirmNoShow;
  final void Function(String runId, RosterStudent student) onConfirmRevert;
  final void Function(String riderId) onOpenNoShow;
}
