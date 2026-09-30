import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/delay/data/models/delay_request.dart';
import 'package:manager_app/features/delay/data/models/delay_result.dart';

/// DelayScreen — 지연 알림 전송 (API_SPEC §4.9, M-05), 동승자 전용
/// (role_policy.dart `canSendDelayNotification`).
///
/// 사유 입력·전송만 이번 범위다 — 알림 수신 확인·이력 조회는 두지 않는다.
class DelayScreen extends ConsumerStatefulWidget {
  const DelayScreen({super.key});

  @override
  ConsumerState<DelayScreen> createState() => _DelayScreenState();
}

class _DelayScreenState extends ConsumerState<DelayScreen> {
  int _minutes = 5;
  DelayReason _reason = DelayReason.traffic;
  final _messageController = TextEditingController();

  bool _submitting = false;
  String? _errorMessage;
  DelayResult? _result;

  static const _reasonOptions = [
    BaraedaSegmentedOption('traffic', label: '교통 체증'),
    BaraedaSegmentedOption('weather', label: '기상 악화'),
    BaraedaSegmentedOption('vehicle_check', label: '차량 점검'),
    BaraedaSegmentedOption('prev_stop_wait', label: '이전 승하차지 대기'),
  ];

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
      setState(() => _result = result);
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

    return Scaffold(
      appBar: AppBar(title: const Text('지연 알림')),
      body: runId == null
          ? const Center(child: Text('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
          : !canSend
          ? const Center(child: Text('동승자만 지연 알림을 보낼 수 있습니다'))
          : _buildBody(runId),
    );
  }

  Widget _buildBody(String runId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            AlertBanner(tone: AlertTone.missed, body: _errorMessage),
            const SizedBox(height: 12),
          ],
          if (_result != null) ...[
            AlertBanner(
              tone: AlertTone.boarded,
              body: _describeResult(_result!),
            ),
            const SizedBox(height: 12),
          ],
          DelayPicker(
            value: _minutes,
            onChanged: _submitting
                ? null
                : (value) => setState(() => _minutes = value),
          ),
          const SizedBox(height: 16),
          const Text('지연 사유'),
          const SizedBox(height: 8),
          BaraedaSegmentedControl(
            options: _reasonOptions,
            value: _reason.wireValue,
            block: true,
            // 칸이 4개라 좁은 폭·큰 글자에서 낱말 중간에서 끊긴다 — 낱말 단위로 줄을 바꾼다(R46).
            wrapByWord: true,
            onChanged: _submitting
                ? null
                : (value) => setState(
                    () => _reason = DelayReason.values.firstWhere(
                      (reason) => reason.wireValue == value,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          BaraedaTextarea(
            label: '안내 문구 (선택)',
            hint: '비워두면 사유 기반 문구가 자동으로 사용됩니다',
            enabled: !_submitting,
            controller: _messageController,
          ),
          const SizedBox(height: 8),
          Text(_previewText(), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          BaraedaButton(
            label: '지연 알림 보내기',
            size: BaraedaButtonSize.lg,
            onPressed: _submitting ? null : () => _submit(runId),
          ),
        ],
      ),
    );
  }

  /// 보내기 전에 학부모·학생에게 나갈 문구를 보여준다(R46). 입력한 문구는 그대로 — 사양이 정한 앞머리
  /// "{이름} 학생이 탄 버스 — " 만 붙는다(API_SPEC §4.9). 비우면 자동 문구인데 그 문장은 서버만 만든다(사유별 문장을
  /// 앱이 따로 들고 있으면 서버가 바뀔 때 어긋난다) — 사양에 있는 것(사유·"현재 예상 지연 N분")만 알린다.
  String _previewText() {
    final message = _messageController.text.trim();
    if (message.isNotEmpty) {
      return '학부모·학생에게 이렇게 나갑니다 — "○○ 학생이 탄 버스 — $message"';
    }
    final reasonLabel = _reasonOptions
        .firstWhere((option) => option.value == _reason.wireValue)
        .label;
    return '안내 문구를 비우면 자동 문구가 나갑니다 — '
        '"$reasonLabel" 사유와 "현재 예상 지연 $_minutes분" 이 들어갑니다';
  }

  String _describeResult(DelayResult result) {
    final notified = <String>[
      if (result.notifiedGuardians) '보호자',
      if (result.notifiedStudents) '학생',
      if (result.notifiedStaff) '직원',
    ];
    if (notified.isEmpty) return '알림을 보냈지만 수신 대상이 없습니다';
    return '${notified.join(' · ')}에게 알림을 보냈습니다';
  }
}
