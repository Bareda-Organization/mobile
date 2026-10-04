import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/time/run_time_labels.dart';
import 'package:manager_app/core/ui/bottom_action_bar.dart';
import 'package:manager_app/core/ui/choice_tile_grid.dart';
import 'package:manager_app/core/ui/info_rows_card.dart';
import 'package:manager_app/core/ui/limited_text_controller.dart';
import 'package:manager_app/core/ui/manager_header.dart';
import 'package:manager_app/features/delay/data/models/delay_request.dart';
import 'package:manager_app/features/delay/data/models/delay_result.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

/// DelayScreen — 지연 알림 전송 (API_SPEC §4.9, M-05), 동승자 전용
/// (role_policy.dart `canSendDelayNotification`). 시안 `delay` · `delay--sent`.
///
/// 분(5분 단위 스텝퍼) · 사유(카드 4칸) · 안내 문구를 고르고 `N분 지연 알림 보내기`(M4)를 누른다. 보낸 뒤에는
/// 폼 대신 **영수증**(지연 시간 · 사유 · 보낸 시각 · 받은 사람)을 보여 주고, 상황이 달라지면 `다시 보내기` 로
/// 같은 값이 채워진 폼으로 돌아간다. 알림 수신 확인·이력 조회는 두지 않는다.
class DelayScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DelayScreen> createState() => _DelayScreenState();
}

/// 방금 보낸 알림 — 영수증이 이 값을 그린다(폼 값이 아니라 **보낸 시점의 값**이어야 다시 보내기로 폼을 고쳐도
/// 영수증이 바뀌지 않는다).
class _Receipt {
  const new({
    required this.minutes,
    required this.reason,
    required this.sentAt,
    required this.result,
  });

  final int minutes;
  final DelayReason reason;
  final DateTime sentAt;
  final DelayResult result;
}

class _DelayScreenState extends ConsumerState<DelayScreen> {
  static const _minMinutes = 5;
  static const _maxMinutes = 30;
  static const _stepMinutes = 5;

  int _minutes = _minMinutes;
  DelayReason _reason = DelayReason.traffic;
  final _messageController = TextEditingController();

  bool _submitting = false;
  String? _errorMessage;
  _Receipt? _receipt;

  static final List<ChoiceTileOption<DelayReason>> _reasonOptions = [
    _reasonOption(DelayReason.traffic, 'route'),
    _reasonOption(DelayReason.weather, 'triangle-alert'),
    _reasonOption(DelayReason.vehicleCheck, 'bus'),
    _reasonOption(DelayReason.prevStopWait, 'users-round'),
  ];

  /// 글자는 학부모 앱의 지연 띠와 같이 읽는 표(`delayReasonLabel`)에서 가져온다 —
  /// 사유를 더하면 표에도 넣는다(`delay_reason_label_test` 가 빠뜨림을 잡는다).
  static ChoiceTileOption<DelayReason> _reasonOption(
    DelayReason reason,
    String icon,
  ) => ChoiceTileOption(
    value: reason,
    label: delayReasonLabel(reason.wireValue)!,
    icon: icon,
  );

  @override
  void initState() {
    super.initState();
    // 문구를 입력할 때마다 미리보기를 다시 그린다(R46).
    _messageController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  String _reasonLabel(DelayReason reason) =>
      _reasonOptions.firstWhere((option) => option.value == reason).label;

  Future<void> _submit(String runId) async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final message = _messageController.text.trim();
      final result = await ref
          .read(delayRepositoryProvider)
          .sendDelay(
            runId: runId,
            request: DelayRequest(
              minutes: _minutes,
              reason: _reason,
              message: message.isEmpty ? null : message,
            ),
          );
      if (!mounted) return;
      setState(
        () => _receipt = _Receipt(
          minutes: _minutes,
          reason: _reason,
          sentAt: ref.read(clockProvider).now(),
          result: result,
        ),
      );
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);
    final capabilities = ref.watch(roleCapabilitiesProvider);
    final canSend = capabilities?.canSendDelayNotification ?? false;
    final run = ref.watch(selectedManagerRunProvider);

    return Scaffold(
      appBar: ManagerHeader(
        title: '지연 알림',
        subtitle: run == null
            ? null
            : '${run.busNo} · ${directionLabel(run.direction)}',
      ),
      body: runId == null
          ? const Center(child: WordWrapText('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
          : !canSend
          ? const Center(child: WordWrapText('동승자만 지연 알림을 보낼 수 있습니다'))
          : _receipt != null
          ? _buildReceipt(_receipt!)
          : _buildForm(runId),
    );
  }

  Widget _buildForm(String runId) {
    final colors = context.colors;
    Widget label(String text) => Text(
      text,
      style: BaraedaTypography.label.copyWith(color: colors.textPrimary),
    );
    return Column(
      children: [
        Expanded(
          // 폼은 항목이 몇 개 안 돼 한꺼번에 만든다 — 화면 밖 카드도 위젯 시험이 바로 찾는다.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  AlertBanner(tone: AlertTone.missed, body: _errorMessage),
                  const SizedBox(height: 12),
                ],
                label('얼마나 늦어요?'),
                const SizedBox(height: 8),
                _MinuteStepper(
                  minutes: _minutes,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _minutes = value),
                ),
                const SizedBox(height: 16),
                label('왜 늦어요?'),
                const SizedBox(height: 8),
                ChoiceTileGrid<DelayReason>(
                  options: _reasonOptions,
                  value: _reason,
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _reason = value),
                ),
                const SizedBox(height: 16),
                BaraedaTextarea(
                  label: '안내 문구 (선택)',
                  hint: '비워두면 사유로 자동 문구가 만들어져요 · $freeTextPrivacyNotice',
                  rows: 2,
                  enabled: !_submitting,
                  controller: _messageController,
                ),
                const SizedBox(height: 16),
                _buildPreview(),
              ],
            ),
          ),
        ),
        BottomActionBar(
          children: [
            BaraedaButton(
              label: '$_minutes분 지연 알림 보내기',
              icon: 'clock',
              size: BaraedaButtonSize.xl,
              block: true,
              onPressed: _submitting ? null : () => _submit(runId),
            ),
          ],
        ),
      ],
    );
  }

  /// 보내기 전에 학부모·학생에게 나갈 문구를 보여준다(R46). 입력한 문구는 그대로 — 사양이 정한 앞머리
  /// "{이름} 학생이 탄 버스 — " 만 붙는다(API_SPEC §4.9). 비우면 자동 문구인데 그 문장은 서버만 만든다(사유별 문장을
  /// 앱이 따로 들고 있으면 서버가 바뀔 때 어긋난다) — 사양에 있는 것(사유·"현재 예상 지연 N분")만 알린다.
  Widget _buildPreview() {
    final colors = context.colors;
    final message = _messageController.text.trim();
    final style = BaraedaTypography.caption.copyWith(
      color: colors.textSecondary,
      height: 1.5,
    );
    final first = message.isNotEmpty
        ? '학부모·학생에게 이렇게 나가요 — "○○ 학생이 탄 버스 — $message"'
        : '문구를 비우면 자동 문구가 나가요. "${_reasonLabel(_reason)}" 사유와 '
              '"현재 예상 지연 $_minutes분" 이 들어가요.';
    return BaraedaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '이렇게 나가요',
            style: BaraedaTypography.label.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 6),
          WordWrapText(first, style: style),
          const SizedBox(height: 8),
          WordWrapText('받는 사람 · 학원 관계자 + 다음 승하차지 이후의 학생 · 학부모', style: style),
        ],
      ),
    );
  }

  Widget _buildReceipt(_Receipt receipt) {
    final colors = context.colors;
    final receivers = <String>[
      if (receipt.result.notifiedStaff) '관계자',
      if (receipt.result.notifiedGuardians) '학부모',
      if (receipt.result.notifiedStudents) '학생',
    ].join(' · ');
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AlertBanner(
                tone: AlertTone.boarded,
                title: '알림을 보냈어요',
                body: receivers.isEmpty
                    ? '받을 사람이 없어 전달되지 않았어요.'
                    : '$receivers에게 전달됐어요.',
              ),
              const SizedBox(height: 12),
              InfoRowsCard(
                rows: [
                  InfoRow('지연 시간', value: '${receipt.minutes}분'),
                  InfoRow('사유', value: _reasonLabel(receipt.reason)),
                  InfoRow(
                    '보낸 시각',
                    value: DateFormat('HH:mm:ss').format(receipt.sentAt),
                  ),
                  InfoRow('받은 사람', value: receivers.isEmpty ? '없음' : receivers),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '상황이 달라지면 같은 화면에서 다시 보낼 수 있어요.',
                style: BaraedaTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        BottomActionBar(
          children: [
            BaraedaButton(
              label: '명단으로',
              size: BaraedaButtonSize.xl,
              block: true,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: 4),
            BaraedaButton(
              label: '다시 보내기',
              variant: BaraedaButtonVariant.ghost,
              block: true,
              onPressed: () => setState(() => _receipt = null),
            ),
          ],
        ),
      ],
    );
  }
}

/// `− 10분 +` 5분 단위 스텝퍼(시안 `delay`). 5분에서 줄이기, 30분에서 늘리기가 꺼진다.
class _MinuteStepper extends StatelessWidget {
  const new({required this.minutes, required this.onChanged});

  final int minutes;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canDecrease =
        onChanged != null && minutes > _DelayScreenState._minMinutes;
    final canIncrease =
        onChanged != null && minutes < _DelayScreenState._maxMinutes;
    Widget stepButton(String icon, String label, VoidCallback? onTap) =>
        SizedBox(
          width: 56,
          height: 56,
          child: BaraedaIconButton(
            icon: icon,
            label: label,
            size: 56,
            tone: BaraedaIconButtonTone.soft,
            onPressed: onTap,
          ),
        );
    return BaraedaCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          stepButton(
            'minus',
            '${_DelayScreenState._stepMinutes}분 줄이기',
            canDecrease
                ? () => onChanged!(minutes - _DelayScreenState._stepMinutes)
                : null,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$minutes', style: BaraedaTypography.h1),
                    const TextSpan(text: '분', style: BaraedaTypography.h3),
                  ],
                ),
                style: TextStyle(color: colors.textPrimary),
              ),
              Text(
                '${_DelayScreenState._stepMinutes}분 단위로 바꿔요',
                style: BaraedaTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          stepButton(
            'plus',
            '${_DelayScreenState._stepMinutes}분 늘리기',
            canIncrease
                ? () => onChanged!(minutes + _DelayScreenState._stepMinutes)
                : null,
          ),
        ],
      ),
    );
  }
}
