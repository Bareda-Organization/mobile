import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/emergency/data/models/emergency_item.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_request.dart';
import 'package:manager_app/features/emergency/data/models/emergency_raise_result.dart';
import 'package:manager_app/features/emergency/data/models/emergency_type.dart';
import 'package:manager_app/features/emergency/presentation/emergency_providers.dart';
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
/// 실시간 확인 반영(WS `emergency_acked`)은 F4 범위라 이 화면은 목록 조회
/// (진입 시 + 수동 새로고침)로만 `acked` 상태를 갱신한다 — WebSocket
/// 클라이언트를 두지 않는다(지시서 범위 제한).
class EmergencyScreen extends ConsumerStatefulWidget {
  const EmergencyScreen({super.key});

  @override
  ConsumerState<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends ConsumerState<EmergencyScreen> {
  EmergencyType _type = EmergencyType.accident;
  final _memoController = TextEditingController();

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
    try {
      final outcome = await ref
          .read(emergencyRepositoryProvider)
          .raise(
            runId: runId,
            request: EmergencyRaiseRequest(
              type: _type,
              clientKey: IdempotencyKeys.generate(),
              memo: memo.isEmpty ? null : memo,
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
          ? const Center(child: Text('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
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
            error: (error, _) => Text('이력을 불러오지 못했습니다: $error'),
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
          hint: '무슨 일이 있었는지 적어 주세요',
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
    return Column(
      children: [
        for (final item in items) ...[
          _buildListItem(runId, item, now),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  String _buildRaisedNotice(EmergencyRaiseResult result) {
    final until = DateFormat('HH:mm:ss').format(result.cancelableUntil);
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
          Text(DateFormat('HH:mm:ss').format(item.raisedAt)),
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
      return byName == null ? '확인됨' : '$byName 님이 확인함';
    }
    return '확인 대기 중';
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
