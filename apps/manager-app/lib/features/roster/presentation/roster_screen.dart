import 'dart:async';

import 'package:baraeda_app/baraeda_app.dart';
import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
import 'package:manager_app/features/roster/domain/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/domain/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_actions.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/widgets/revert_confirm_sheet.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_interaction.dart';
import 'package:manager_app/features/roster/presentation/widgets/roster_view.dart';

/// 명단(§4.2 M-03 · §4.6 M-12 · §4.7 M-13 · §4.8 M-14 · §4.11 M-04 변경 확인).
///
/// 동승자는 이 화면이 아래 탭 첫 칸이고 승하차를 처리한다([readOnly] 가 `false`). 기사는 운행 화면의 `명단 ›` 로
/// 열어 보기만 한다([readOnly] — 시안 `roster-driver`, 승차 · 하차는 동승자가 한다). 지금 곳(다음 도착)은 늘
/// 펼쳐 있고 그 밖의 곳은 접혀 있어 눌러 펼친다(동승자가 직접 펼칠 수 있다). 지난 곳은 한 줄로 묶는다.
///
/// 처리 단추는 `canDecideBoardingStatus`(동승자 전용, role_policy.dart)로만 노출된다. 변경 확인 띠는
/// `ChangeAckBanner` 가 맡는다(§4.1 `ack_required` — 운행 화면도 같은 띠를 쓴다).
class RosterScreen extends ConsumerStatefulWidget {
  const new({super.key, this.readOnly = false});

  /// 기사의 조회 전용 열람 — 처리 단추 · 지연 알림 · 대기열이 없고 뒤로 가기가 있다.
  final bool readOnly;

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  /// 응답을 기다리는 학생들 — 한 명이 아니라 집합이다. 여러 학생을 연달아 눌러도 앞 학생의 잠금이 풀리지 않는다.
  final Set<String> _pendingRiderIds = {};
  String? _errorMessage;

  /// 사용자가 직접 펼친 승하차지 · 지난 곳 묶음을 펼쳤는가.
  final Set<String> _expandedStopIds = {};
  bool _pastExpanded = false;

  /// 기기에 저장해 둔 명단을 보는 동안 서버에서 다시 받아 보는 주기 — 연결이 돌아오면 저장본이 서버
  /// 명단으로 바뀐다. 서버에서 받은 명단이면 아무것도 하지 않는다.
  static const _cachedRetryInterval = Duration(seconds: 15);
  Timer? _cachedRetryTimer;

  @override
  void initState() {
    super.initState();
    _cachedRetryTimer = Timer.periodic(_cachedRetryInterval, (_) {
      if (ref.read(rosterProvider).value?.cachedAt != null) {
        ref.invalidate(rosterProvider);
      }
    });
  }

  @override
  void dispose() {
    _cachedRetryTimer?.cancel();
    super.dispose();
  }

  /// [미승차]는 [탑승] 옆에 있어 잘못 눌리기 쉽고, 처리하면 관계자에게 바로(학부모에게는 이
  /// 승하차지를 출발할 때 — `Ruling 854`) 알림이 나간다 — 한 번 묻는다. 취소하면 요청을 보내지 않는다.
  Future<void> _confirmNoShow(String runId, String riderId, String name) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '$name 학생을 미승차로 처리할까요?',
      body:
          '처리하면 관계자에게는 바로, 학부모에게는 이 승하차지를 출발할 때 알림이 나가고 '
          '연락 대기 시간이 시작돼요.',
      confirmLabel: '미승차 처리',
      cancelLabel: '닫기',
    );
    if (!confirmed || !mounted) return;
    await _updateStatus(runId, riderId, RiderStatus.noShow);
  }

  Future<void> _updateStatus(
    String runId,
    String riderId,
    RiderStatus status,
  ) async {
    setState(() {
      _pendingRiderIds.add(riderId);
      _errorMessage = null;
    });
    try {
      // 즉시 전송과 재생(큐 재시도) 양쪽이 같은 client_key 를 쓰도록 여기서
      // 한 번만 만든다 — repository 가 재생 시 새로 만들지 않고 이 값을
      // 그대로 들고 있는다(payload 에 실려 drift 에 저장되므로).
      final outcome = await ref
          .read(rosterRepositoryProvider)
          .updateRiderStatus(
            runId: runId,
            riderId: riderId,
            request: BoardingUpdateRequest(
              status: status,
              clientKey: IdempotencyKeys.generate(),
              // 누른 시각 — 오프라인 재생분이 서버에 도착한 시각으로 기록되지 않게 한다.
              occurredAt: ref.read(clockProvider).now(),
            ),
          );
      if (!mounted) return;
      switch (outcome) {
        case Sent():
          ref
            ..invalidate(rosterProvider)
            ..invalidate(pendingRequestsProvider);
        case Queued():
          // 서버에 아직 반영되지 않았으니 명단을 다시 불러오지 않는다 —
          // §1.9 낙관적 표시 금지와 같은 이유. 대기 안내·행 표시는 큐 목록에서 그린다.
          ref.invalidate(pendingRequestsProvider);
      }
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
      // Ruling 345 — 같은 상태 재요청 포함, 다른 사람이 이미 처리했을
      // 수 있어 낡은 화면이 그대로 남지 않도록 명단을 다시 불러온다.
      if (failure case ApiFailure(code: 'RIDER_TRANSITION_NOT_ALLOWED')) {
        ref.invalidate(rosterProvider);
      }
    } finally {
      if (mounted) setState(() => _pendingRiderIds.remove(riderId));
    }
  }

  /// 되돌리기는 잘못 눌렀을 때 쓰는 조작이라 한 번 묻는다(시안 `undo`). 닫으면 요청이 없다.
  Future<void> _confirmRevert(String runId, RosterStudent student) async {
    final confirmed = await showRevertConfirmSheet(context, student: student);
    if (!confirmed || !mounted) return;
    await _revertStatus(runId, student.riderId);
  }

  Future<void> _revertStatus(String runId, String riderId) async {
    // 요청 중에 화면이 닫혀도 명단은 갱신해야 한다 — 닫힌 화면의 `ref` 는 쓸 수 없어 컨테이너를 쥔다.
    final container = ProviderScope.containerOf(context);
    setState(() {
      _pendingRiderIds.add(riderId);
      _errorMessage = null;
    });
    try {
      await ref
          .read(rosterRepositoryProvider)
          .revertRiderStatus(runId: runId, riderId: riderId);
      container.invalidate(rosterProvider);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _pendingRiderIds.remove(riderId));
    }
  }

  /// [미승차 연락] 화면으로 — 학생 하나의 연락 대기 · 기록을 본다.
  void _openNoShow(String riderId) =>
      unawaited(context.push('${AppRoutes.noShow}?rider=$riderId'));

  /// 명단의 보호자 번호는 마스킹이라 걸 수 없다 — [전화] 를 누른 순간 그 학생 1명의 원번호를
  /// 서버에서 받아 `tel:` 로 연다(Ruling 482). 원번호는 화면에 싣지 않고 바로 전화 앱에 넘긴다.
  /// 번호를 못 받으면 걸지 않고 이유를 알린다.
  Future<void> _callGuardianOf(String runId, String riderId) async {
    setState(() {
      _pendingRiderIds.add(riderId);
      _errorMessage = null;
    });
    final error = await callGuardian(ref, runId: runId, riderId: riderId);
    if (!mounted) return;
    setState(() {
      _pendingRiderIds.remove(riderId);
      _errorMessage = error;
    });
  }

  /// 명단을 그리는 화면에 넘길 조작 상태와 처리 콜백.
  RosterInteraction _interaction() => RosterInteraction(
    readOnly: widget.readOnly,
    pendingRiderIds: _pendingRiderIds,
    expandedStopIds: _expandedStopIds,
    pastExpanded: _pastExpanded,
    errorMessage: _errorMessage,
    onToggleStop: _toggleStop,
    onTogglePast: () => setState(() => _pastExpanded = !_pastExpanded),
    onCall: _callGuardianOf,
    onUpdateStatus: _updateStatus,
    onConfirmNoShow: _confirmNoShow,
    onConfirmRevert: _confirmRevert,
    onOpenNoShow: _openNoShow,
  );

  void _toggleStop(String stopId) => setState(() {
    if (!_expandedStopIds.remove(stopId)) _expandedStopIds.add(stopId);
  });

  @override
  Widget build(BuildContext context) => RosterView(interaction: _interaction());
}
