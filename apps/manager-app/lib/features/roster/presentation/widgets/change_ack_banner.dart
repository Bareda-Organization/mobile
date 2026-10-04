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
/// `todayRunsProvider` 를 다시 받아 서버 값으로 바꾼다. 확인한 뒤에는 초록 "확인했어요" 로 바뀐다.
class ChangeAckBanner extends ConsumerStatefulWidget {
  const new({
    required this.runId,
    required this.ackRequired,
    super.key,
    this.addedCount = 0,
    this.removedCount = 0,
    this.bottomGap = 0,
  });

  final String runId;
  final bool ackRequired;

  /// §4.1 `added_count` · `removed_count` — 띠에 `추가 1곳 · 삭제 1곳` 으로 적는다. 둘 다 0
  /// 이면 일반 문구.
  final int addedCount;
  final int removedCount;

  /// 띠가 보일 때만 아래에 두는 간격 — 안 보일 때(확인할 변경이 없을 때)는 자리를 차지하지 않는다.
  final double bottomGap;

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
    // 확인한 뒤 서버가 `ack_required=false` 로 돌려줘도 "확인했어요" 는 화면이 떠 있는 동안 남긴다 —
    // 새 변경으로 다시 켜질 때(false → true)만 지운다.
    if (!oldWidget.ackRequired && widget.ackRequired) _acked = false;
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

  /// `추가 1곳 · 삭제 1곳` — 0 인 쪽은 적지 않는다. 둘 다 0 이면 일반 문구.
  String get _countsLabel {
    final parts = [
      if (widget.addedCount > 0) '추가 ${widget.addedCount}곳',
      if (widget.removedCount > 0) '삭제 ${widget.removedCount}곳',
    ];
    return parts.isEmpty ? '승하차지·명단이 바뀌었어요' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (_acked) {
      return Padding(
        padding: EdgeInsets.only(bottom: widget.bottomGap),
        child: AlertBanner(
          tone: AlertTone.boarded,
          icon: 'check',
          title: '노선 변경을 확인했어요',
          body: _countsLabel,
        ),
      );
    }
    if (!widget.ackRequired) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AlertBanner(
            tone: AlertTone.moving,
            icon: 'route',
            title: '노선이 바뀌었어요',
            body: _countsLabel,
            inlineAction: true,
            action: BaraedaButton(
              label: '변경 확인',
              size: BaraedaButtonSize.sm,
              variant: BaraedaButtonVariant.secondary,
              onPressed: _acking ? null : _ack,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            AlertBanner(tone: AlertTone.missed, body: _errorMessage),
          ],
        ],
      ),
    );
  }
}
