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
    BaraedaSegmentedOption('prev_stop_wait', label: '이전 정류장 대기'),
  ];

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
