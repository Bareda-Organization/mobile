import 'dart:async';

import 'package:baraeda_app/baraeda_app.dart';
import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/location/position_source.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/ui/academy_call_card.dart';
import 'package:manager_app/core/ui/limited_text_controller.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/core/ui/saved_runs_notice.dart';
import 'package:manager_app/features/emergency/domain/models/emergency_raise_request.dart';
import 'package:manager_app/features/emergency/domain/models/emergency_raise_result.dart';
import 'package:manager_app/features/emergency/domain/models/emergency_type.dart';
import 'package:manager_app/features/emergency/presentation/emergency_providers.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_body.dart';
import 'package:manager_app/features/offline_queue/domain/send_outcome.dart';
import 'package:manager_app/features/offline_queue/presentation/offline_queue_providers.dart';

/// 확인 대기 중 비상 이력을 다시 받는 주기 — 실시간 채널이 없는 곳의 대체 수단이라 짧게 잡는다.
const emergencyAckPollInterval = Duration(seconds: 10);

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
/// 진입점은 홈·운행·명단 화면 머리말의 `EmergencyButton` 이다.
/// 실시간 확인 반영(WS `emergency_acked`, Ruling 277)은 이 화면이
/// 직접 구독하지 않는다 — `ManagerRunChannelController`(DriveMode·StopRoster 가 호스팅)가
/// `emergency_acked` 를 받을 때마다 `emergencyListProvider` 를 무효화해 둔다. 그 채널이 없는 곳
/// (홈 · 알림 · 내 정보 · 운행 준비)에서 보낸 신고는 확인 대기 동안 [emergencyAckPollInterval] 마다 이력을
/// 다시 받아 "학원이 확인했어요" 로 바뀐다 — 별도 WebSocket 클라이언트를 이 화면에 두지 않는다.
class EmergencyScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<EmergencyScreen> createState() => _EmergencyScreenState();
}

const _offlineStrip = BaraedaConnectionStrip(
  state: BaraedaConnectionState.offline,
  message: '인터넷 연결 없음 · 연결되면 자동으로 보내요',
);

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

  late final VisiblePoller _ackPoller = VisiblePoller(
    interval: emergencyAckPollInterval,
    onTick: _pollAck,
  );

  /// 방금 보낸 신고가 아직 확인 전이면 이력을 다시 받는다. 보내기 전 · 확인된 뒤 · 새 신고 작성 중에는 아무 일도 없다.
  void _pollAck() {
    final raised = _lastRaised;
    if (!mounted || raised == null || _composing) return;
    final item = ref
        .read(emergencyListProvider)
        .value
        ?.items
        .where((item) => item.emergencyId == raised.emergencyId)
        .firstOrNull;
    if (item != null && item.acked) return;
    ref.invalidate(emergencyListProvider);
  }

  @override
  void initState() {
    super.initState();
    _ackPoller.start();
  }

  @override
  void dispose() {
    _ackPoller.dispose();
    _memoController.dispose();
    super.dispose();
  }

  /// §4.14 발신. `type=etc` 는 `memo` 가 필수(§4.14 `422 VALIDATION_FAILED`
  /// 조건) — 서버 왕복 없이 화면에서 먼저 막는다.
  Future<void> _submit(String runId) async {
    // 재진입 가드 — 1회 측정(sampleOnce)을 기다리는 동안 버튼이 아직
    // 비활성으로 다시 그려지기 전이면(pump 전) 두 번째 탭이 옛 onPressed
    // 를 그대로 다시 부를 수 있다. 이 가드가 없으면 그 재호출도 끝까지
    // 진행돼 중복 발신이 나간다.
    if (_submitting) return;
    final memo = _memoController.text.trim();
    if (_type == EmergencyType.etc && memo.isEmpty) {
      setState(() => _errorMessage = '기타 유형은 상황 메모가 필요해요');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
      _queuedAt = null;
    });
    final sample = await _currentPosition(ref.read(positionSourceProvider));
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

  /// 상황이 바뀌면 같은 화면에서 다시 보낸다 — 작성 화면으로 돌아가며 지난 발송 · 오류를 비운다.
  void _resend() => setState(() {
    _composing = true;
    _lastRaised = null;
    _queuedAt = null;
    _errorMessage = null;
  });

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);
    final unsent = runId == null || _composing
        ? null
        : latestUnsentEmergency(ref.watch(pendingRequestsProvider).value);
    final failed = unsent != null || (_queuedAt != null && !_composing);
    return Scaffold(
      appBar: ManagerHeader(
        title: '비상 알림',
        showSos: false,
        // 서버에 닿지 못한 신고가 있으면 맨 위에 연결 끊김 띠(시안 `emergency--failed`).
        strip: failed ? _offlineStrip : null,
      ),
      body: Column(
        children: [
          // 오늘 회차 목록이 저장본이면 홈과 같은 안내를 맨 위에 띄운다.
          const SavedRunsBanner(),
          Expanded(
            child: runId == null
                ? const _NoRunNotice()
                : EmergencyBody(
                    unsent: unsent,
                    failed: failed,
                    composing: _composing,
                    lastRaised: _lastRaised,
                    lastRaisedType: _lastRaisedType,
                    queuedAt: _queuedAt,
                    queuedType: _queuedType,
                    type: _type,
                    errorMessage: _errorMessage,
                    cancelErrorMessage: _cancelErrorMessage,
                    cancelingId: _cancelingId,
                    submitting: _submitting,
                    memoController: _memoController,
                    onTypeChanged: (value) => setState(() => _type = value),
                    onSubmit: () => _submit(runId),
                    onResend: _resend,
                    onCancel: (emergencyId) => _cancel(runId, emergencyId),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 발신에 실을 좌표 — 스트림의 최신 값이 없으면 1회 측정으로 보완한다.
///
/// §4.14 가 미전달 시 서버의 최신 수신 좌표 대체를 규정한다 — 비상은
/// 운행 전·후나 GPS 송신이 끊긴 뒤에도 나므로, 그 대체값이 최신
/// 좌표보다 나은 판단은 아니다. 비상은 기사·동승자 둘 다 발신하고
/// (ARCHITECTURE §3.3·EXC-04) positionSourceProvider 자체는 역할과
/// 무관하게 읽을 수 있지만, 위치 스트림([PositionSource.start])은
/// `Ruling 360` 이후 기사 운행 화면에서만 열린다 — 동승자 단말이나
/// 송신이 끊긴 기사 단말은 `sample()` 이 늘 `null` 이다. 그때만 1회
/// 측정(sampleOnce)으로 보완한다(포그라운드 서비스는 켜지 않는다).
/// 제한 시간 안에 못 받거나 거부되면 좌표 없이
/// 그대로 진행한다 — 좌표를 지어내지 않는다.
Future<PositionSample?> _currentPosition(PositionSource source) async {
  final sample = source.sample();
  return sample ?? await source.sampleOnce();
}

/// 선택된 회차가 없을 때의 막다른 화면 — 안내만 두지 않고 급하면 학원에 바로 전화할 수 있게 한다.
class _NoRunNotice extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: WordWrapText('선택된 운행이 없어요 — 홈에서 운행을 선택하세요')),
          SizedBox(height: 16),
          AcademyCallCard(lead: '급하면 먼저 전화하세요'),
        ],
      ),
    );
  }
}
