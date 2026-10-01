import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/launcher/device_launchers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/ui/limited_text_controller.dart';
import 'package:manager_app/features/emergency/data/models/emergency_item.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_request.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_result.dart';
import 'package:manager_app/features/emergency/data/models/emergency_type.dart';
import 'package:manager_app/features/emergency/presentation/emergency_providers.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_button.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';

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
/// 진입점은 홈·운행·명단 화면 머리말의 [EmergencyButton] 이다(R32 M2 — 그 전에는 라우트만
/// 있고 갈 길이 없었다). 실시간 확인 반영(WS `emergency_acked`, Ruling 277)은 이 화면이
/// 직접 구독하지 않는다 — `ManagerRunChannelController`(DriveMode·StopRoster 가 호스팅)가
/// `emergency_acked` 를 받을 때마다 `emergencyListProvider` 를 무효화해 두므로, 이 화면에
/// 들어오면(재진입 시 재조회) 이미 최신 `acked` 상태를 본다 — 별도 WebSocket 클라이언트를
/// 이 화면에 두지 않는다(보고서 §1).
class EmergencyScreen extends ConsumerStatefulWidget {
  const EmergencyScreen({super.key});

  @override
  ConsumerState<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends ConsumerState<EmergencyScreen> {
  EmergencyType _type = EmergencyType.accident;
  final _memoController = LimitedTextController();

  bool _submitting = false;
  String? _errorMessage;
  String? _queueNotice;
  EmergencyRaiseResult? _lastRaised;

  String? _cancelingId;
  String? _cancelErrorMessage;

  static const _typeOptions = [
    BaraedaSegmentedOption('accident', label: '사고'),
    BaraedaSegmentedOption('vehicle_fault', label: '차량 고장'),
    BaraedaSegmentedOption('student_emergency', label: '학생 응급'),
    BaraedaSegmentedOption('etc', label: '기타'),
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
      _queueNotice = null;
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
          setState(() => _lastRaised = value);
          ref.invalidate(emergencyListProvider);
        case Queued():
          // AlertTone.info 는 쓰지 않는다 — baraeda_ui 의 아이콘 매핑표
          // (widgets/core/icon.dart)에 'info' 글리프가 없어 디버그 모드에서
          // 단언 실패로 렌더링이 죽는다(roster_screen.dart 가 같은 이유로
          // 이미 우회함 — baraeda_ui 자체는 이번 범위 밖). 아래에서
          // AlertTone.moving 을 재사용한다.
          setState(() => _queueNotice = '처리되지 않았습니다 · 대기 중');
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
    return Scaffold(
      appBar: AppBar(title: const Text('비상 알림')),
      body: runId == null
          ? const Center(child: WordWrapText('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
          : _buildBody(runId),
    );
  }

  Widget _buildBody(String runId) {
    final listAsync = ref.watch(emergencyListProvider);
    // 위젯 안에서 `DateTime.now()` 를 직접 부르지 않는다
    // (CONVENTIONS_FLUTTER.md §9, 이월 11) — 취소 가능 창 판정에 쓴다.
    final now = ref.watch(clockProvider).now();

    return RefreshIndicator(
      onRefresh: () => ref.refresh(emergencyListProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_errorMessage != null) ...[
            AlertBanner(tone: AlertTone.missed, body: _errorMessage),
            const SizedBox(height: 12),
          ],
          if (_queueNotice != null) ...[
            // 비상이 서버에 닿지 못했다 — 아무에게도 안 갔으니 사람에게 직접 알려야 한다(R46).
            AlertBanner(
              tone: AlertTone.missed,
              body: '전송 안 됨 — 학원에 전화하세요',
              action: _buildCallAcademyButton(),
            ),
            const SizedBox(height: 12),
            AlertBanner(tone: AlertTone.moving, body: _queueNotice),
            const SizedBox(height: 12),
          ],
          if (_lastRaised != null) ...[
            AlertBanner(
              tone: AlertTone.boarded,
              body: _buildRaisedNotice(_lastRaised!),
              action: now.isBefore(_lastRaised!.cancelableUntil)
                  ? _buildCancelButton(runId, _lastRaised!.emergencyId)
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          _buildForm(runId),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('발신 이력', style: Theme.of(context).textTheme.titleMedium),
              // 아이콘 전용 새로고침 버튼을 쓰지 않는다 — 아이콘 매핑표에
              // 새로고침 계열 글리프(refresh-cw 등)가 없다. 텍스트 라벨
              // 버튼으로 대신한다.
              BaraedaButton(
                label: '새로고침',
                size: BaraedaButtonSize.sm,
                variant: BaraedaButtonVariant.ghost,
                onPressed: () => ref.invalidate(emergencyListProvider),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_cancelErrorMessage != null) ...[
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
            data: (list) => _buildList(runId, list.items, now),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(String runId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('비상 상황 유형'),
        const SizedBox(height: 8),
        BaraedaSegmentedControl(
          options: _typeOptions,
          value: _type.wireValue,
          block: true,
          // 칸이 4개라 좁은 폭·큰 글자에서 낱말 중간에서 끊긴다 — 낱말 단위로 줄을 바꾼다(R46).
          wrapByWord: true,
          onChanged: _submitting
              ? null
              : (value) => setState(
                  () => _type = EmergencyType.values.firstWhere(
                    (type) => type.wireValue == value,
                  ),
                ),
        ),
        const SizedBox(height: 16),
        BaraedaTextarea(
          label: _type == EmergencyType.etc ? '상황 메모 (필수)' : '상황 메모 (선택)',
          hint: '무슨 일이 있었는지 적어 주세요 · $freeTextPrivacyNotice',
          enabled: !_submitting,
          controller: _memoController,
        ),
        const SizedBox(height: 20),
        BaraedaButton(
          label: '비상 알림 보내기',
          variant: BaraedaButtonVariant.danger,
          size: BaraedaButtonSize.lg,
          onPressed: _submitting ? null : () => _submit(runId),
        ),
      ],
    );
  }

  Widget _buildList(String runId, List<EmergencyItem> items, DateTime now) {
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
          _buildListItem(runId, item, now),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  String _buildRaisedNotice(EmergencyRaiseResult result) {
    final until = DateFormat(
      'HH:mm:ss',
    ).format(result.cancelableUntil.toLocal());
    return '비상 알림을 보냈습니다 (${result.notified}명에게 전달) — '
        '$until 까지 취소할 수 있습니다';
  }

  Widget _buildListItem(String runId, EmergencyItem item, DateTime now) {
    final canceled = item.canceledAt != null;
    final status = canceled
        ? BaraedaStatus.idle
        : item.acked
        ? BaraedaStatus.boarded
        : BaraedaStatus.missed;
    final canCancel =
        !canceled && !item.acked && now.isBefore(item.cancelableUntil);

    return BaraedaCard(
      accent: status,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.type.label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(DateFormat('HH:mm:ss').format(item.raisedAt.toLocal())),
          const SizedBox(height: 4),
          Text(_statusLabelOf(item, canceled)),
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

  /// 학원 대표 연락처로 전화를 건다 — 번호를 모르면(학원이 등록하지 않음) 버튼 없이 안내 문구만 남긴다.
  Widget? _buildCallAcademyButton() {
    final contact = ref.watch(academyContactProvider);
    if (contact == null || contact.trim().isEmpty) return null;
    return BaraedaButton(
      label: '학원에 전화',
      size: BaraedaButtonSize.sm,
      variant: BaraedaButtonVariant.danger,
      onPressed: () => unawaited(
        ref.read(uriOpenerProvider)(Uri(scheme: 'tel', path: contact.trim())),
      ),
    );
  }

  Widget _buildCancelButton(String runId, String emergencyId) {
    final canceling = _cancelingId == emergencyId;
    return BaraedaButton(
      label: '취소',
      variant: BaraedaButtonVariant.danger,
      size: BaraedaButtonSize.sm,
      onPressed: canceling ? null : () => _cancel(runId, emergencyId),
    );
  }
}
