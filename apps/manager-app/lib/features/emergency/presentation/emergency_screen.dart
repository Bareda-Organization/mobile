import 'dart:async';
import 'dart:convert';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/academy_call_card.dart';
import 'package:manager_app/core/ui/bottom_action_bar.dart';
import 'package:manager_app/core/ui/choice_tile_grid.dart';
import 'package:manager_app/core/ui/info_rows_card.dart';
import 'package:manager_app/core/ui/limited_text_controller.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/emergency/data/models/emergency_item.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_request.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_result.dart';
import 'package:manager_app/features/emergency/data/models/emergency_type.dart';
import 'package:manager_app/features/emergency/presentation/emergency_providers.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_views.dart';
import 'package:manager_app/features/offline_queue/data/models/pending_request_summary.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

/// EmergencyScreen — 비상 발신·취소·이력 조회 (API_SPEC §4.14·§4.15, M-15,
/// UF-X-08). 기사·동승자 둘 다 호출 가능해 역할 제한을 두지 않는다
/// (`EmergencyRepository` 문서 주석과 같은 판단 — `role_policy.dart` 에
/// capability 를 추가하지 않는다).
///
/// 중복 발신을 막지 않는다 — §4.14 가 "상황 변화마다 재발신이 정상" 이라고
/// 명시한다. 취소 가능 창(발신 후 1분)은 서버가 준 `cancelable_until` 로만
/// 판단한다 — 클라이언트가 `발신 시각 + 1분` 을 계산하면 단말·서버 시계가
/// 어긋났을 때(clock skew) 실제와 다른 창을 보여준다.
///
/// 진입점은 홈·운행·명단 화면 머리말의 `EmergencyButton` 이다(R32 M2 — 그 전에는 라우트만
/// 있고 갈 길이 없었다). 실시간 확인 반영(WS `emergency_acked`, Ruling 277)은 이 화면이
/// 직접 구독하지 않는다 — `ManagerRunChannelController`(DriveMode·StopRoster 가 호스팅)가
/// `emergency_acked` 를 받을 때마다 `emergencyListProvider` 를 무효화해 두므로, 이 화면에
/// 들어오면(재진입 시 재조회) 이미 최신 `acked` 상태를 본다 — 별도 WebSocket 클라이언트를
/// 이 화면에 두지 않는다(보고서 §1).
class EmergencyScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends ConsumerState<EmergencyScreen> {
  EmergencyType _type = EmergencyType.accident;
  final _memoController = LimitedTextController();

  bool _submitting = false;
  String? _errorMessage;
  EmergencyRaiseResult? _lastRaised;
  EmergencyType? _lastRaisedType;

  /// 서버에 닿지 못해 큐에 쌓인 신고 — 누른 시각 · 유형(전송 실패 화면의 정보 표).
  DateTime? _queuedAt;
  EmergencyType? _queuedType;

  /// `새 상황으로 다시 보내기` 를 눌렀다 — 발송 결과 · 전송 실패 화면 대신 작성 화면을 보인다.
  bool _composing = false;

  String? _cancelingId;
  String? _cancelErrorMessage;

  static const List<ChoiceTileOption<EmergencyType>> _typeOptions = [
    ChoiceTileOption(
      value: EmergencyType.accident,
      label: '사고',
      icon: 'triangle-alert',
    ),
    ChoiceTileOption(
      value: EmergencyType.vehicleFault,
      label: '차량 고장',
      icon: 'bus',
    ),
    ChoiceTileOption(
      value: EmergencyType.studentEmergency,
      label: '학생 응급',
      icon: 'user-round',
    ),
    ChoiceTileOption(
      value: EmergencyType.etc,
      label: '기타',
      icon: 'info',
      hint: '메모 필수',
    ),
  ];

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  /// §4.14 발신. `type=etc` 는 `memo` 가 필수(§4.14 `422 VALIDATION_FAILED`
  /// 조건) — 서버 왕복 없이 화면에서 먼저 막는다.
  Future<void> _submit(String runId) async {
    // 재진입 가드 — 1회 측정(sampleOnce)을 기다리는 동안 버튼이 아직
    // 비활성으로 다시 그려지기 전이면(pump 전) 두 번째 탭이 옛 onPressed
    // 를 그대로 다시 부를 수 있다. 이 가드가 없으면 그 재호출도 끝까지
    // 진행돼 중복 발신이 나간다(BRIEF-BG2 "중복 발신 방지").
    if (_submitting) return;
    final memo = _memoController.text.trim();
    if (_type == EmergencyType.etc && memo.isEmpty) {
      setState(() => _errorMessage = '기타 유형은 상황 메모가 필요합니다');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
      _queuedAt = null;
    });
    // §4.14 가 미전달 시 서버의 최신 수신 좌표 대체를 규정한다 — 비상은
    // 운행 전·후나 GPS 송신이 끊긴 뒤에도 나므로, 그 대체값이 최신
    // 좌표보다 나은 판단은 아니다. 비상은 기사·동승자 둘 다 발신하고
    // (ARCHITECTURE §3.3·EXC-04) positionSourceProvider 자체는 역할과
    // 무관하게 읽을 수 있지만, 위치 스트림([PositionSource.start])은
    // `Ruling 360` 이후 기사 운행 화면에서만 열린다 — 동승자 단말이나
    // 송신이 끊긴 기사 단말은 `sample()` 이 늘 `null` 이다. 그때만 1회
    // 측정(sampleOnce)으로 보완한다(포그라운드 서비스는 켜지 않는다,
    // BRIEF-BG2). 제한 시간 안에 못 받거나 거부되면 지금처럼 좌표 없이
    // 그대로 진행한다 — 좌표를 지어내지 않는다.
    final positionSource = ref.read(positionSourceProvider);
    var sample = positionSource.sample();
    sample ??= await positionSource.sampleOnce();
    if (!mounted) return;
    try {
      final outcome = await ref
          .read(emergencyRepositoryProvider)
          .raise(
            runId: runId,
            request: EmergencyRaiseRequest(
              type: _type,
              clientKey: IdempotencyKeys.generate(),
              memo: memo.isEmpty ? null : memo,
              // §4.14 는 occurred_at 을 "오프라인 발신분의 실제 시각"으로
              // 규정하고, 비상 발신은 §1.7 오프라인 큐 대상이다 — 통신이
              // 끊겼다 나중에 복구되면 서버는 수신 시각만 갖게 돼 실제
              // 발생 시각을 잃는다. 위젯 안에서 `DateTime.now()` 를 직접
              // 부르지 않는다(CONVENTIONS_FLUTTER.md §9, 이월 11) —
              // clockProvider 로 주입받는다.
              occurredAt: ref.read(clockProvider).now(),
              lat: sample?.lat,
              lng: sample?.lng,
            ),
          );
      if (!mounted) return;
      switch (outcome) {
        case Sent(:final value):
          setState(() {
            _lastRaised = value;
            _lastRaisedType = _type;
            _composing = false;
          });
          ref.invalidate(emergencyListProvider);
        case Queued():
          // 전송 실패 화면(시안 `emergency--failed`)으로 바뀐다 — 큐가 성공할 때까지 계속 다시 보낸다.
          setState(() {
            _queuedAt = ref.read(clockProvider).now();
            _queuedType = _type;
            _composing = false;
          });
          // 방금 쌓인 신고를 큐 목록에 반영해 위 전송 실패 안내가 바로 뜨게 한다.
          ref.invalidate(pendingRequestsProvider);
      }
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// §4.14 취소 — 1분 창이 지났거나 이미 확인된 건이면 서버가 `409` 로
  /// 막는다(`EMERGENCY_CANCEL_WINDOW_CLOSED`). 버튼 노출 자체는 클라이언트가
  /// 미리 가려 왕복을 줄이지만, 최종 판정은 항상 서버 응답이다.
  Future<void> _cancel(String runId, String emergencyId) async {
    setState(() {
      _cancelingId = emergencyId;
      _cancelErrorMessage = null;
    });
    try {
      await ref
          .read(emergencyRepositoryProvider)
          .cancel(runId: runId, emergencyId: emergencyId);
      if (!mounted) return;
      setState(() {
        if (_lastRaised?.emergencyId == emergencyId) _lastRaised = null;
      });
      ref.invalidate(emergencyListProvider);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _cancelErrorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _cancelingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);
    final unsent = runId == null || _composing ? null : _unsentEmergency();
    final failed = unsent != null || (_queuedAt != null && !_composing);
    return Scaffold(
      appBar: ManagerHeader(
        title: '비상 알림',
        showSos: false,
        // 서버에 닿지 못한 신고가 있으면 맨 위에 연결 끊김 띠(시안 `emergency--failed`).
        strip: failed
            ? const BaraedaConnectionStrip(
                state: BaraedaConnectionState.offline,
                message: '인터넷 연결 없음 · 연결되면 자동으로 보내요',
              )
            : null,
      ),
      body: runId == null
          ? const Center(child: WordWrapText('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
          : _buildBody(runId, unsent: unsent, failed: failed),
    );
  }

  /// 큐에서 아직 안 나간 비상 신고 가운데 가장 나중 것 — 이 화면에서 누른 것뿐 아니라 앞서 쌓인 것도 센다.
  /// 영구 실패로 굳은 행(`failed`)은 "계속 다시 보내는 중" 이 아니라 세지 않는다(Ruling 616).
  PendingRequestSummary? _unsentEmergency() {
    final pending = ref.watch(pendingRequestsProvider).value;
    if (pending == null) return null;
    PendingRequestSummary? latest;
    for (final request in pending) {
      if (!request.isEmergency || request.failed) continue;
      if (latest == null || request.createdAt.isAfter(latest.createdAt)) {
        latest = request;
      }
    }
    return latest;
  }

  Widget _buildBody(
    String runId, {
    required PendingRequestSummary? unsent,
    required bool failed,
  }) {
    final listAsync = ref.watch(emergencyListProvider);
    // 위젯 안에서 `DateTime.now()` 를 직접 부르지 않는다
    // (CONVENTIONS_FLUTTER.md §9, 이월 11) — 취소 가능 창 판정에 쓴다.
    final now = ref.watch(clockProvider).now();
    final raised = _composing ? null : _lastRaised;
    final focus = raised == null
        ? null
        : listAsync.value?.items
              .where((item) => item.emergencyId == raised.emergencyId)
              .firstOrNull;

    final Widget content;
    final List<Widget> footer;
    if (failed) {
      content = _buildFailed(unsent);
      footer = [_resendButton()];
    } else if (raised != null) {
      content = focus != null && focus.acked
          ? _buildAcked(focus)
          : _buildSent(runId, raised);
      footer = focus != null && focus.acked ? const [] : [_resendButton()];
    } else {
      content = _buildForm();
      footer = [_sendButton(runId)];
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(emergencyListProvider.future),
            // 내용이 길지 않아 한꺼번에 만든다 — 화면 밖 이력 카드도 위젯 시험이 바로 찾는다.
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  content,
                  if (!failed) ...[
                    const SizedBox(height: 24),
                    _buildHistory(
                      runId,
                      listAsync,
                      now,
                      excludeId: raised?.emergencyId,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (footer.isNotEmpty) BottomActionBar(children: footer),
      ],
    );
  }

  // ── 작성(시안 `emergency`) ──────────────────────────────────────────

  Widget _buildForm() {
    final colors = context.colors;
    final run = ref.watch(selectedManagerRunProvider);
    final sample = ref.read(positionSourceProvider).sample();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 급하면 먼저 전화(M2) — 번호는 저장된 학원 연락처이고, 번호 모양이 아니면 그리지 않는다.
        const AcademyCallCard(lead: '급하면 먼저 전화하세요'),
        const SizedBox(height: 16),
        if (_errorMessage != null) ...[
          AlertBanner(tone: AlertTone.missed, body: _errorMessage),
          const SizedBox(height: 12),
        ],
        Text(
          '무슨 일이에요?',
          style: BaraedaTypography.label.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 8),
        ChoiceTileGrid<EmergencyType>(
          options: _typeOptions,
          value: _type,
          onChanged: _submitting
              ? null
              : (value) => setState(() => _type = value),
        ),
        const SizedBox(height: 16),
        BaraedaTextarea(
          label: _type == EmergencyType.etc ? '상황 메모 (필수)' : '상황 메모 (선택)',
          hint: '무슨 일이 있었는지 적어 주세요 · $freeTextPrivacyNotice',
          rows: 2,
          enabled: !_submitting,
          controller: _memoController,
        ),
        const SizedBox(height: 16),
        Text(
          '함께 보내는 정보',
          style: BaraedaTypography.label.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 8),
        InfoRowsCard(
          rows: [
            InfoRow(
              '회차',
              value: run == null
                  ? '선택한 회차'
                  : '${run.busNo} · ${directionLabel(run.direction)} '
                        '${hhmm(run.departTime)}',
            ),
            InfoRow(
              '현재 위치',
              value: sample == null
                  ? '서버가 받은 마지막 위치'
                  : '현재 위치 · ${hhmm(sample.recordedAt)} 측정',
            ),
            const InfoRow('받는 사람', value: '학원 관계자 · 메인 관리자'),
          ],
        ),
      ],
    );
  }

  Widget _sendButton(String runId) => BaraedaButton(
    label: '비상 알림 보내기',
    icon: 'triangle-alert',
    variant: BaraedaButtonVariant.danger,
    size: BaraedaButtonSize.xl,
    block: true,
    onPressed: _submitting ? null : () => _submit(runId),
  );

  /// 상황이 바뀌면 같은 화면에서 다시 보낸다 — 지우기 어려운 빨간 면이 아니라 테두리 단추(M3).
  Widget _resendButton() => BaraedaButton(
    label: '새 상황으로 다시 보내기',
    icon: 'triangle-alert',
    variant: BaraedaButtonVariant.dangerOutline,
    block: true,
    onPressed: () => setState(() {
      _composing = true;
      _lastRaised = null;
      _queuedAt = null;
      _errorMessage = null;
    }),
  );

  // ── 발송 뒤(시안 `emergency--sent`) ─────────────────────────────────

  Widget _buildSent(String runId, EmergencyRaiseResult raised) {
    final type = _lastRaisedType?.label ?? '비상';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_cancelErrorMessage != null) ...[
          AlertBanner(tone: AlertTone.missed, body: _cancelErrorMessage),
          const SizedBox(height: 12),
        ],
        EmergencyStatusCard(
          title: '비상 알림을 보냈어요',
          subtitle:
              '학원 관계자·메인 관리자 ${raised.notified}명에게 전달 · $type · '
              '${_time(raised.raisedAt)}',
          below: [
            EmergencyCancelWindow(
              raisedAt: raised.raisedAt,
              cancelableUntil: raised.cancelableUntil,
              canceling: _cancelingId == raised.emergencyId,
              onCancel: () => _cancel(runId, raised.emergencyId),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const EmergencySteps(
          steps: [
            EmergencyStep(title: '발송 완료', detail: '위치 · 회차 · 연락처가 함께 갔어요'),
            EmergencyStep(
              title: '학원이 확인하면 여기에 표시돼요',
              detail: '확인되면 "○○ 님이 확인함" 으로 바뀌어요',
              done: false,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const EmergencyCallButton(),
      ],
    );
  }

  // ── 학원이 확인함(시안 `emergency--ack`) ────────────────────────────

  Widget _buildAcked(EmergencyItem item) {
    final colors = context.colors;
    final by = item.ackedByName;
    final who = (by == null || by.isEmpty) ? '학원' : '$by 관계자';
    final ackedAt = item.ackedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmergencyStatusCard(
          title: '학원이 확인했어요',
          subtitle:
              '$who · ${ackedAt == null ? '' : '${_time(ackedAt)} · '}'
              '${item.type.label}',
          below: const [EmergencyCallButton()],
        ),
        const SizedBox(height: 12),
        EmergencySteps(
          steps: [
            EmergencyStep(
              title: '발송 완료',
              detail: '${_time(item.raisedAt)} · 위치 · 회차 · 연락처가 함께 갔어요',
            ),
            EmergencyStep(
              title: '학원이 확인함',
              detail: [
                ?ackedAt == null ? null : _time(ackedAt),
                who,
              ].join(' · '),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '운행은 그대로 이어져요. 상황이 바뀌면 학원에 전화로 알려 주세요.',
          style: BaraedaTypography.caption.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ── 전송 실패(시안 `emergency--failed`) ─────────────────────────────

  Widget _buildFailed(PendingRequestSummary? unsent) {
    final colors = context.colors;
    final type = _typeOfQueued(unsent) ?? _queuedType;
    final pressedAt = unsent?.createdAt ?? _queuedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AlertBanner(
          tone: AlertTone.missed,
          title: '전송 실패 — 계속 다시 보내는 중',
          body: '아직 아무에게도 닿지 않았어요. 급하면 학원에 바로 전화해 주세요.',
        ),
        const SizedBox(height: 12),
        const EmergencyCallButton(danger: true),
        const SizedBox(height: 12),
        InfoRowsCard(
          rows: [
            InfoRow('유형', value: type?.label ?? '비상 알림'),
            if (pressedAt != null) InfoRow('누른 시각', value: _time(pressedAt)),
            InfoRow(
              '상태',
              valueWidget: Row(
                children: [
                  const BaraedaStatusPill(
                    status: BaraedaStatus.waiting,
                    label: '전송 대기',
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '연결되면 자동 전송',
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        WordWrapText(
          '비상 알림은 포기하지 않고 성공할 때까지 다시 보내요. 서버에는 누른 시각이 아니라 받은 시각이 기록돼요. '
          '못 보낸 처리는 내 정보 ▸ 오프라인 대기열에서도 볼 수 있어요.',
          style: BaraedaTypography.caption.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }

  /// 큐에 쌓인 신고 본문(`{"type":"accident",…}`)에서 유형을 읽는다 — 읽지 못하면 `null`.
  EmergencyType? _typeOfQueued(PendingRequestSummary? request) {
    if (request == null) return null;
    try {
      final decoded = jsonDecode(request.payload);
      if (decoded is Map<String, dynamic>) {
        return EmergencyType.fromWireValueOrNull(decoded['type'] as String?);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String _time(DateTime value) =>
      DateFormat('HH:mm:ss').format(value.toLocal());

  // ── 오늘 보낸 비상 알림 ─────────────────────────────────────────────

  Widget _buildHistory(
    String runId,
    AsyncValue<EmergencyListResponse> listAsync,
    DateTime now, {
    String? excludeId,
  }) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '오늘 보낸 비상 알림',
                style: BaraedaTypography.title.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            listAsync.maybeWhen(
              data: (list) => Text(
                '${list.items.length}건',
                style: BaraedaTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_cancelErrorMessage != null && _lastRaised == null) ...[
          AlertBanner(tone: AlertTone.missed, body: _cancelErrorMessage),
          const SizedBox(height: 12),
        ],
        listAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              WordWrapText('이력을 불러오지 못했습니다: ${describeError(error)}'),
          data: (list) => _buildList(runId, list.items, now, excludeId),
        ),
      ],
    );
  }

  Widget _buildList(
    String runId,
    List<EmergencyItem> items,
    DateTime now,
    String? excludeId,
  ) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: 'bell',
        title: '발신한 비상 알림이 없습니다',
        body: '비상 상황이 생기면 위에서 바로 보낼 수 있습니다',
      );
    }
    // stretch 가 없으면 카드가 내용 폭으로 줄어 가운데에 뜬다(R46-SCREEN 화면 확인 — 폭 ~30%).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items) ...[
          _buildListItem(runId, item, now, excludeId),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildListItem(
    String runId,
    EmergencyItem item,
    DateTime now,
    String? excludeId,
  ) {
    final colors = context.colors;
    final canceled = item.canceledAt != null;
    final status = canceled
        ? BaraedaStatus.idle
        : item.acked
        ? BaraedaStatus.boarded
        : BaraedaStatus.waiting;
    // 방금 보낸 알림의 취소는 위 카드가 맡는다 — 같은 알림에 취소 단추가 둘이 되지 않게 한다.
    final canCancel =
        !canceled &&
        !item.acked &&
        now.isBefore(item.cancelableUntil) &&
        item.emergencyId != excludeId;
    return BaraedaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceSunken,
                  borderRadius: BorderRadius.circular(BaraedaRadius.control),
                ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: BaraedaIcon(
                      'triangle-alert',
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: BaraedaSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.type.label} · ${_time(item.raisedAt)}',
                      style: BaraedaTypography.body.copyWith(
                        color: colors.textPrimary,
                        fontWeight: BaraedaFontWeight.bold,
                      ),
                    ),
                    Text(
                      _statusLabelOf(item, canceled),
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              BaraedaStatusPill(
                status: status,
                label: canceled
                    ? '취소됨'
                    : item.acked
                    ? '확인함'
                    : '확인 대기',
              ),
            ],
          ),
          if (canCancel) ...[
            const SizedBox(height: 8),
            _buildCancelButton(runId, item.emergencyId),
          ],
        ],
      ),
    );
  }

  String _statusLabelOf(EmergencyItem item, bool canceled) {
    if (canceled) return '취소됨';
    if (item.acked) {
      final byName = item.ackedByName;
      return (byName == null || byName.isEmpty) ? '확인됨' : '$byName 님이 확인함';
    }
    return '확인 대기 중';
  }

  Widget _buildCancelButton(String runId, String emergencyId) {
    final canceling = _cancelingId == emergencyId;
    return BaraedaButton(
      label: '취소',
      variant: BaraedaButtonVariant.dangerOutline,
      size: BaraedaButtonSize.sm,
      onPressed: canceling ? null : () => _cancel(runId, emergencyId),
    );
  }
}
