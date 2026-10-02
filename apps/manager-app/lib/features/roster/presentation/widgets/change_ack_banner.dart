import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/features/home/presentation/home_providers.dart';

/// 노선 변경 확인 띠(§4.11 · M-04 · RUN-07) — 확정 뒤 승하차지·명단이 바뀌면
/// 기사·동승자 둘 다 확인해야 한다. 명단 화면과 운행 화면이 같은 띠를 쓴다
/// (R32 M4 — 기사는 명단에 가지 않아 운행 화면에도 있어야 한다).
///
/// 노출 여부는 §4.1 `ack_required` 가 정하고([ackRequired]), 확인이 성공하면
/// `todayRunsProvider` 를 다시 받아 서버 값으로 바꾼다. 다시 받기 전 깜빡이지
/// 않도록 성공 즉시 스스로 숨긴다.
class ChangeAckBanner extends ConsumerStatefulWidget {
  const new({
    required this.runId,
    required this.ackRequired,
    super.key,
  });

  final String runId;
  final bool ackRequired;

  @override
  ConsumerState<ChangeAckBanner> createState() => _ChangeAckBannerState();
}

class _ChangeAckBannerState extends ConsumerState<ChangeAckBanner> {
  bool _acking = false;
  bool _acked = false;
  String? _errorMessage;

  @override
  void didUpdateWidget(ChangeAckBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 서버 값(`ack_required`)이 바뀌면 이 화면이 기억한 "확인했음" 은 그 변경에 대한 것이었다 —
    // 다음 노선 변경으로 다시 켜질 때 띠가 뜨도록 지운다(F06-08).
    if (oldWidget.ackRequired != widget.ackRequired) _acked = false;
  }

  Future<void> _ack() async {
    final container = ProviderScope.containerOf(context);
    setState(() {
      _acking = true;
      _errorMessage = null;
    });
    try {
      await ref.read(rosterRepositoryProvider).ackChanges(runId: widget.runId);
      container.invalidate(todayRunsProvider);
      if (!mounted) return;
      setState(() => _acked = true);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _errorMessage = describeFailure(failure));
    } finally {
      if (mounted) setState(() => _acking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.ackRequired || _acked) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AlertBanner(
          tone: AlertTone.moving,
          body: '승하차지·명단이 변경됐습니다 — 확인 후 계속 진행하세요',
        ),
        const SizedBox(height: 8),
        BaraedaButton(
          label: '변경 목록 확인',
          onPressed: _acking ? null : _ack,
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          AlertBanner(tone: AlertTone.missed, body: _errorMessage),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
