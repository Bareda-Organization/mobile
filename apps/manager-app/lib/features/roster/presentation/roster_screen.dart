import 'dart:async';
import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/app_routes.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/constants/api_constants.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/manager_channel_banner.dart';
import 'package:manager_app/core/run/run_enums.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/ui/confirm_dialog.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_button.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/roster/data/models/boarding_update_request.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';
import 'package:manager_app/features/roster/data/models/roster_response.dart';
import 'package:manager_app/features/roster/presentation/roster_photo.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';
import 'package:manager_app/features/roster/presentation/widgets/change_ack_banner.dart';

/// StopRoster — 정류장별 탑승자 명단 (§4.2 M-03 · §4.6 M-12 · §4.7 M-13 ·
/// §4.8 M-14 · §4.11 M-04 변경 확인).
///
/// 기사·동승자 둘 다 조회하지만(API_SPEC "버스기사(조회)"), 승하차 상태를
/// 바꾸는 버튼은 `canDecideBoardingStatus`(동승자 전용, role_policy.dart)
/// 로만 노출된다 — 같은 화면에서 버튼 노출이 갈리는 또 다른 예시(§1.1).
/// §4.11 변경 확인 응답은 기사·동승자 둘 다 호출 가능해 capability 분기를
/// 두지 않았다(정본 "권한 버스기사 · 동승자" 그대로). 배너 노출 여부는
/// `selectedManagerRunProvider`(§4.1 `ack_required`, RUN-07)를 근거로
/// 삼는다 — `GET /roster`(§4.2) 응답에는 이 플래그가 없어, 확인 응답이
/// 성공하면 `todayRunsProvider` 를 무효화해 서버 값을 다시 받는다 — 띠와 그 동작은
/// [ChangeAckBanner] 가 맡고 운행 화면도 같은 띠를 쓴다(R32 M4). 서버 쪽 미확인 표시는
/// 관계자 대시보드(MON-05)의 몫이라 이 화면이 다시 확인하지 않는다.
class RosterScreen extends ConsumerStatefulWidget {
  const RosterScreen({super.key});

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  String? _pendingRiderId;
  String? _errorMessage;

  /// §1.7 M-06 — 통신 두절로 큐에 쌓인 승하차 처리를 알리는 문구
  /// ("처리되지 않았습니다 · 대기 중"). §1.9 는 성공을 미리 보여주는 것을
  /// 금지할 뿐이라, 실패(`_errorMessage`, `AlertTone.missed`)와는 다른
  /// 어조로 따로 보여준다 — 대기 중은 실패가 아니다. `AlertTone.info` 는
  /// 쓰지 않는다 — baraeda_ui 의 아이콘 매핑표(icon.dart)에 'info' 글리프가
  /// 없어 디버그 모드에서 단언 실패로 렌더링이 죽는다(run_end_screen.dart
  /// 도 같은 이유로 우회함 — baraeda_ui 는 이번 라운드 범위 밖). 이 화면
  /// 위쪽의 "변경 목록 확인" 안내와 같은 `AlertTone.moving` 을 재사용한다.
  String? _queueNotice;

  /// 그 학생의 미승차 대기가 끝나는 시각 — 명단 응답의 `no_show_case.expires_at` 이다. 서버가
  /// 학원 설정(A-17, 기본 3분)으로 계산해 주므로 앱에 대기 시간 상수를 두지 않는다(R32 M12).
  DateTime? _waitEndsAtOf(RosterResponse roster, String riderId) {
    for (final stop in roster.stops) {
      for (final student in stop.students) {
        if (student.riderId == riderId) return student.noShowCase?.expiresAt;
      }
    }
    return null;
  }

  /// 학생 이름 — 확인 창 문구용. 명단에 없으면 "학생" 으로 쓴다.
  String _nameOf(RosterResponse roster, String riderId) {
    for (final stop in roster.stops) {
      for (final student in stop.students) {
        if (student.riderId == riderId) return student.name;
      }
    }
    return '학생';
  }

  /// [미승차]는 [탑승] 옆에 있어 잘못 눌리기 쉽고, 처리하면 학부모에게 알림이 나간다 — 한 번
  /// 묻는다(R32 M7). 취소하면 요청을 보내지 않는다.
  Future<void> _confirmNoShow({
    required String runId,
    required String riderId,
    required String name,
  }) async {
    final confirmed = await confirmAction(
      context,
      title: '$name 학생을 미승차로 처리할까요?',
      body: '처리하면 학부모·관계자에게 바로 알림이 나가고 연락 대기 시간이 시작됩니다',
      confirmLabel: '미승차 처리',
    );
    if (!confirmed || !mounted) return;
    await _updateStatus(
      runId: runId,
      riderId: riderId,
      status: RiderStatus.noShow,
    );
  }

  Future<void> _updateStatus({
    required String runId,
    required String riderId,
    required RiderStatus status,
  }) async {
    setState(() {
      _pendingRiderId = riderId;
      _errorMessage = null;
      _queueNotice = null;
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
              // 누른 시각 — 오프라인 재생분이 서버에 도착한 시각으로 기록되지 않게 한다(F06-05).
              occurredAt: ref.read(clockProvider).now(),
            ),
          );
      if (!mounted) return;
      switch (outcome) {
        case Sent():
          ref.invalidate(rosterProvider);
        case Queued():
          // 서버에 아직 반영되지 않았으니 명단을 다시 불러오지 않는다 —
          // §1.9 낙관적 표시 금지와 같은 이유.
          setState(() => _queueNotice = '처리되지 않았습니다 · 대기 중');
      }
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
      // M3(Ruling 345) — 같은 상태 재요청 포함, 다른 사람이 이미 처리했을
      // 수 있어 낡은 화면이 그대로 남지 않도록 명단을 다시 불러온다.
      if (failure case ApiFailure(code: 'RIDER_TRANSITION_NOT_ALLOWED')) {
        ref.invalidate(rosterProvider);
      }
    } finally {
      if (mounted) setState(() => _pendingRiderId = null);
    }
  }

  Future<void> _revertStatus({
    required String runId,
    required String riderId,
  }) async {
    // 요청 중에 화면이 닫혀도 명단은 갱신해야 한다 — 닫힌 화면의 `ref` 는 쓸 수 없어 컨테이너를 쥔다(F06-16).
    final container = ProviderScope.containerOf(context);
    setState(() {
      _pendingRiderId = riderId;
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
      if (mounted) setState(() => _pendingRiderId = null);
    }
  }

  Future<void> _recordNoShowContact({
    required String runId,
    required String riderId,
    DateTime? waitEndsAt,
  }) async {
    final clock = ref.read(clockProvider);
    final request = await showModalBottomSheet<NoShowContactRequest>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _NoShowContactSheet(waitEndsAt: waitEndsAt, clock: clock),
    );
    if (request == null || !mounted) return;
    final container = ProviderScope.containerOf(context);
    setState(() {
      _pendingRiderId = riderId;
      _errorMessage = null;
    });
    try {
      await ref
          .read(rosterRepositoryProvider)
          .recordNoShowContact(
            runId: runId,
            riderId: riderId,
            request: request,
          );
      container.invalidate(rosterProvider);
    } on Failure catch (failure) {
      // Z-05 — 다른 사람이 미승차를 되돌렸다면 이 화면의 명단이 낡았다. 다시 불러온다.
      if (failure case ApiFailure(code: 'NO_SHOW_CASE_NOT_FOUND')) {
        container.invalidate(rosterProvider);
      }
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _pendingRiderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);

    // 사양이 정한 진입점 — 둘 다 **명단 화면에서** 간다.
    //  · UF-E-05 "명단 → [지연 알림]"  — M-05 는 **동승자 전용**(기사는 운전 중)
    //  · 노선 지도(M-09)는 기사 전용이라 기사가 들어오는 운행 화면에 있다 — 여기에는 두지 않는다(R32 M14)
    // 2026-09-21 까지 이 두 배선이 부재해 화면이 만들어져 있어도 도달할 수 없었다.
    final caps = ref.watch(roleCapabilitiesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('승하차 명단'),
        actions: [
          // 비상(M-15, R32 M2) — 동승자도 발신한다. 노선·연결 상태와 무관하게 늘 보인다.
          const EmergencyButton(),
          // 예외 보고(M-14, R32 M3) — 보호자 부재·도로 통제 등. 기사는 운행 화면의 종료 보고서로,
          // 동승자는 여기서 보고한다.
          TextButton(
            onPressed: () => context.push(AppRoutes.runEnd),
            child: const Text('예외 보고'),
          ),
          if (caps?.canSendDelayNotification ?? false)
            TextButton(
              onPressed: () => context.push(AppRoutes.delay),
              child: const Text('지연 알림'),
            ),
          // ⚠ 오프라인 큐는 **이 화면에서만** 갈 수 있어야 한다.
          // `OfflineQueueScreen` 자바독이 "재전송은 이 화면의 버튼을 눌렀을 때만"
          // 이라고 적는다 — 도달 불가면 통신 두절로 쌓인 승하차 처리가 **영영 안 나간다**.
          // 승하차를 처리하는 주체(동승자)에게 연다(M-06 · UF-E-07).
          if (caps?.canDecideBoardingStatus ?? false)
            TextButton(
              onPressed: () => context.push(AppRoutes.offlineQueue),
              child: const Text('대기열'),
            ),
        ],
      ),
      body: runId == null
          ? const Center(child: Text('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
          : _buildBody(context, runId),
    );
  }

  Widget _buildBody(BuildContext context, String runId) {
    final rosterAsync = ref.watch(rosterProvider);
    final capabilities = ref.watch(roleCapabilitiesProvider);
    final canDecide = capabilities?.canDecideBoardingStatus ?? false;
    final run = ref.watch(selectedManagerRunProvider);

    // ManagerChannelBanner 는 rosterAsync.when(...) 의 모든 분기 바깥에
    // 둔다 — "명단 없음"(정상, data 분기)과 "연결 끊김"(비정상)이 화면에서
    // 구별돼야 한다(목표 9, ManagerChannelBanner 문서 참고).
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: ManagerChannelBanner(runId: runId),
        ),
        Expanded(
          child: rosterAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: Text('명단을 불러오지 못했습니다: ${describeError(error)}')),
            data: (roster) => _buildRoster(
              runId,
              canDecide,
              run?.ackRequired ?? false,
              roster,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoster(
    String runId,
    bool canDecide,
    bool ackRequired,
    RosterResponse roster,
  ) {
    final photoHeaders = ref.watch(rosterPhotoHeadersProvider).value;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ChangeAckBanner(runId: runId, ackRequired: ackRequired),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: '탑승',
                value: '${roster.counts.boarded}',
                tone: StatCardTone.boarded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: '대기',
                value: '${roster.counts.waiting}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: '미승차',
                value: '${roster.counts.noShow}',
                tone: StatCardTone.missed,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: '미등원',
                value: '${roster.counts.absentN}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_errorMessage != null) ...[
          AlertBanner(tone: AlertTone.missed, body: _errorMessage),
          const SizedBox(height: 12),
        ],
        if (_queueNotice != null) ...[
          AlertBanner(tone: AlertTone.moving, body: _queueNotice),
          const SizedBox(height: 12),
        ],
        // 머리 번호는 서버 seq 가 아니라 이 목록의 순번이다 — 서버 seq 는 경유 지점 자리(§4.3)를 비운 채 와서
        // 1·3·4 로 건너뛴다. 지도 핀 번호와 같은 규칙(`Ruling 400`).
        for (final (index, stop) in roster.stops.indexed)
          _StopSection(
            stop: stop,
            order: index + 1,
            photoHeaders: photoHeaders,
            canDecide: canDecide,
            pendingRiderId: _pendingRiderId,
            onBoard: (riderId) => _updateStatus(
              runId: runId,
              riderId: riderId,
              status: RiderStatus.boarded,
            ),
            onAlight: (riderId) => _updateStatus(
              runId: runId,
              riderId: riderId,
              status: RiderStatus.alighted,
            ),
            onNoShow: (riderId) => _confirmNoShow(
              runId: runId,
              riderId: riderId,
              name: _nameOf(roster, riderId),
            ),
            onRevert: (riderId) =>
                _revertStatus(runId: runId, riderId: riderId),
            onRecordContact: (riderId) => _recordNoShowContact(
              runId: runId,
              riderId: riderId,
              waitEndsAt: _waitEndsAtOf(roster, riderId),
            ),
          ),
      ],
    );
  }
}

/// 정류장 한 곳 — 헤더(순번·이름·도착 시각) + 탑승자 행 목록.
///
/// `StopTimeline` 은 정류장 순서 요약(웹·다른 화면)에 쓰는 컴포넌트라 인원
/// 집계까지만 보여준다 — 개인별 행·액션 버튼이 필요한 이 화면에는 맞지
/// 않아 직접 헤더+`StudentRow` 목록을 조합했다(설계 판단, 보고서 참고).
class _StopSection extends StatelessWidget {
  const _StopSection({
    required this.stop,
    required this.order,
    required this.photoHeaders,
    required this.canDecide,
    required this.pendingRiderId,
    required this.onBoard,
    required this.onAlight,
    required this.onNoShow,
    required this.onRevert,
    required this.onRecordContact,
  });

  final RosterStop stop;

  /// 머리에 적는 번호(1부터) — 이 목록에서의 순번.
  final int order;

  /// 사진 요청에 실을 인증 헤더 — 아직 못 읽었으면 `null`(Ruling 377).
  final Map<String, String>? photoHeaders;
  final bool canDecide;
  final String? pendingRiderId;
  final void Function(String riderId) onBoard;
  final void Function(String riderId) onAlight;
  final void Function(String riderId) onNoShow;
  final void Function(String riderId) onRevert;
  final void Function(String riderId) onRecordContact;

  RosterPhoto? _photoOf(RosterStudent student) => resolveRosterPhoto(
    student.photoUrl,
    baseUrl: ApiConstants.baseUrl,
    authHeaders: photoHeaders,
  );

  @override
  Widget build(BuildContext context) {
    final skipped = stop.change == StopChange.skipped;
    final added = stop.change == StopChange.added;
    final arrivedAt = stop.arrivedAt;
    final headerTrailing = skipped
        ? (stop.skipNotice ?? '경유하지 않음')
        : (arrivedAt == null
              ? '미도착'
              : '${DateFormat('HH:mm').format(arrivedAt.toLocal())} 도착');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$order. ${stop.name}',
                style:
                    Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(
                      decoration: skipped ? TextDecoration.lineThrough : null,
                      color: added ? Colors.green.shade700 : null,
                    ),
              ),
              const Spacer(),
              Text(
                headerTrailing,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          for (final student in stop.students)
            StudentRow(
              name: student.name,
              photoUrl: _photoOf(student)?.url,
              photoHeaders: _photoOf(student)?.headers,
              meta: [
                if (student.change == RiderChange.added) '신규',
                student.className,
                student.guardianPhone,
              ].whereType<String>().join(' · '),
              ride: _rideStatusOf(student),
              // M1(Ruling 341, BR-016) — `absent`(`change=removed`) 행은
              // 버스 간 이동으로 빠진 학생이라 조작 대상이 아니다. 배지만
              // 보여주고 [탑승]·[미승차] 등은 아예 그리지 않는다(canDecide
              // 여부와 무관).
              actions: student.status == RiderStatus.absent
                  ? const BaraedaBadge(
                      label: '금일 삭제',
                      tone: BaraedaBadgeTone.removed,
                    )
                  : canDecide
                  ? _StudentActions(
                      student: student,
                      busy: pendingRiderId == student.riderId,
                      onBoard: () => onBoard(student.riderId),
                      onAlight: () => onAlight(student.riderId),
                      onNoShow: () => onNoShow(student.riderId),
                      onRevert: () => onRevert(student.riderId),
                      onRecordContact: () => onRecordContact(student.riderId),
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  RideStatus _rideStatusOf(RosterStudent student) => switch (student.status) {
    RiderStatus.waiting => RideStatus.waiting,
    RiderStatus.boarded => RideStatus.boarded,
    RiderStatus.alighted => RideStatus.alighted,
    RiderStatus.noShow => RideStatus.missed,
    // 이 행은 `actions` 가 이미 "금일 삭제" 배지로 대체해 상태 pill 을
    // 그리지 않지만, `ride` 는 필수 인자라 매핑을 채워 둔다.
    RiderStatus.absent => RideStatus.absent,
  };
}

/// 탑승자 한 명의 상태 전환 버튼 — 현재 [RiderStatus] 에 따라 다음 동작만
/// 보여준다. `busy` 인 동안(요청 진행 중) 전부 비활성화한다.
class _StudentActions extends StatelessWidget {
  const _StudentActions({
    required this.student,
    required this.busy,
    required this.onBoard,
    required this.onAlight,
    required this.onNoShow,
    required this.onRevert,
    required this.onRecordContact,
  });

  final RosterStudent student;
  final bool busy;
  final VoidCallback onBoard;
  final VoidCallback onAlight;
  final VoidCallback onNoShow;
  final VoidCallback onRevert;
  final VoidCallback onRecordContact;

  @override
  Widget build(BuildContext context) {
    // BaraedaIcon 매핑 표(패키지 소유, 이번 라운드에서 건드리지 않음)에
    // "되돌리기"에 맞는 이름이 없어 아이콘 대신 텍스트 버튼을 쓴다.
    final revertButton = BaraedaButton(
      label: '되돌리기',
      size: BaraedaButtonSize.sm,
      variant: BaraedaButtonVariant.ghost,
      onPressed: busy ? null : onRevert,
    );

    switch (student.status) {
      case RiderStatus.waiting:
        return Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BaraedaButton(
              label: '탑승',
              size: BaraedaButtonSize.sm,
              onPressed: busy ? null : onBoard,
            ),
            BaraedaButton(
              label: '미승차',
              size: BaraedaButtonSize.sm,
              variant: BaraedaButtonVariant.danger,
              onPressed: busy ? null : onNoShow,
            ),
          ],
        );
      case RiderStatus.boarded:
        return Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BaraedaButton(
              label: '하차',
              size: BaraedaButtonSize.sm,
              onPressed: busy ? null : onAlight,
            ),
            revertButton,
          ],
        );
      case RiderStatus.noShow:
        final expiresAt = student.noShowCase?.expiresAt;
        return Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (expiresAt != null)
              Text(
                '${DateFormat('HH:mm:ss').format(expiresAt.toLocal())} 만료',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            BaraedaButton(
              label: '연락 기록',
              size: BaraedaButtonSize.sm,
              variant: BaraedaButtonVariant.secondary,
              onPressed: busy ? null : onRecordContact,
            ),
            revertButton,
          ],
        );
      case RiderStatus.alighted:
        return revertButton;
      case RiderStatus.absent:
        // `_StopSection` 이 absent 행에는 이 위젯 자체를 만들지 않는다
        // (배지로 대체) — 도달하지 않지만 exhaustiveness 를 위해 채운다.
        return const SizedBox.shrink();
    }
  }
}

/// §4.8 연락 시도 기록 입력 — 연락 수단·결과·(선택)최종 판단.
///
/// 최종 판단은 대기 시간이 끝난 뒤에만 고를 수 있다 — [waitEndsAt] 까지는 선택지를 끄고 남은 시간을
/// 세어 보인다(R32 M12). [waitEndsAt] 을 모르면(`null`) 막지 않는다 — 서버가 최종 판정한다.
class _NoShowContactSheet extends StatefulWidget {
  const _NoShowContactSheet({required this.waitEndsAt, required this.clock});

  final DateTime? waitEndsAt;
  final Clock clock;

  @override
  State<_NoShowContactSheet> createState() => _NoShowContactSheetState();
}

class _NoShowContactSheetState extends State<_NoShowContactSheet> {
  NoShowAttemptType _attemptType = NoShowAttemptType.call;
  NoShowContactResult _result = NoShowContactResult.noAnswer;
  NoShowDecision? _decision;
  Timer? _ticker;

  /// 대기가 끝나기까지 남은 시간 — 끝났거나 모르면 `Duration.zero`.
  Duration get _remaining {
    final end = widget.waitEndsAt;
    if (end == null) return Duration.zero;
    final left = end.difference(widget.clock.now());
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void initState() {
    super.initState();
    if (_remaining > Duration.zero) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_remaining == Duration.zero) _ticker?.cancel();
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('미탑승 연락 기록', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            const Text('연락 수단'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final type in NoShowAttemptType.values)
                  ChoiceChip(
                    label: Text(type == NoShowAttemptType.call ? '전화' : '문자'),
                    selected: _attemptType == type,
                    onSelected: (_) => setState(() => _attemptType = type),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('결과'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final result in NoShowContactResult.values)
                  ChoiceChip(
                    label: Text(
                      result == NoShowContactResult.answered ? '응답함' : '무응답',
                    ),
                    selected: _result == result,
                    onSelected: (_) => setState(() => _result = result),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('최종 판단 (대기 시간이 끝난 뒤에만 선택)'),
            if (_remaining > Duration.zero)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '대기 시간이 끝나기까지 남은 시간 '
                  '${_remaining.inMinutes}분 '
                  '${(_remaining.inSeconds % 60).toString().padLeft(2, '0')}초',
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('미정'),
                  selected: _decision == null,
                  onSelected: (_) => setState(() => _decision = null),
                ),
                for (final decision in NoShowDecision.values)
                  ChoiceChip(
                    label: Text(
                      decision == NoShowDecision.depart ? '출발 확정' : '재시도',
                    ),
                    selected: _decision == decision,
                    onSelected: _remaining > Duration.zero
                        ? null
                        : (_) => setState(() => _decision = decision),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            BaraedaButton(
              label: '기록 저장',
              block: true,
              onPressed: () => Navigator.of(context).pop(
                NoShowContactRequest(
                  attemptType: _attemptType,
                  result: _result,
                  decision: _decision,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
