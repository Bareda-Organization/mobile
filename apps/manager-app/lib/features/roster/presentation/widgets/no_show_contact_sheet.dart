import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:manager_app/features/roster/data/models/no_show_contact_request.dart';

/// §4.8 연락 시도 기록 입력 시트 — 연락 수단 · 결과 · (선택)최종 판단(시안 `no-show--record`).
///
/// 최종 판단은 대기 시간이 끝난 뒤에만 고를 수 있다 — [waitEndsAt] 까지는 `미정` 만 되고 남은 시간을 세어
/// 보인다(R32 M12). [waitEndsAt] 을 모르면(`null`) 막지 않는다 — 서버가 최종 판정한다.
class NoShowContactSheet extends StatefulWidget {
  const new({required this.waitEndsAt, required this.clock, super.key});

  final DateTime? waitEndsAt;
  final Clock clock;

  @override
  State<NoShowContactSheet> createState() => _NoShowContactSheetState();
}

class _NoShowContactSheetState extends State<NoShowContactSheet> {
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

  Widget _group(String label, Widget control) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: BaraedaTypography.label),
      const SizedBox(height: 8),
      control,
      const SizedBox(height: 16),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final waiting = _remaining > Duration.zero;
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    // 제목·여백·안전 영역·키보드 회피는 BaraedaBottomSheet 가 맡는다.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _group(
          '연락 수단',
          BaraedaSegmentedControl(
            block: true,
            value: _attemptType.wireValue,
            options: const [
              BaraedaSegmentedOption('call', label: '전화'),
              BaraedaSegmentedOption('message', label: '문자'),
            ],
            onChanged: (v) => setState(
              () => _attemptType = NoShowAttemptType.values.firstWhere(
                (t) => t.wireValue == v,
              ),
            ),
          ),
        ),
        _group(
          '결과',
          BaraedaSegmentedControl(
            block: true,
            value: _result.wireValue,
            options: const [
              BaraedaSegmentedOption('answered', label: '응답함'),
              BaraedaSegmentedOption('no_answer', label: '무응답'),
            ],
            onChanged: (v) => setState(
              () => _result = NoShowContactResult.values.firstWhere(
                (r) => r.wireValue == v,
              ),
            ),
          ),
        ),
        _group(
          '최종 판단',
          BaraedaSegmentedControl(
            block: true,
            value: _decision?.wireValue ?? 'none',
            options: const [
              BaraedaSegmentedOption('none', label: '미정'),
              BaraedaSegmentedOption('depart', label: '출발 확정'),
              BaraedaSegmentedOption('retry', label: '재시도'),
            ],
            // 대기 시간이 끝나기 전에는 `미정` 밖을 고를 수 없다.
            onChanged: (v) {
              if (v == 'none') return setState(() => _decision = null);
              if (waiting) return;
              setState(
                () => _decision = NoShowDecision.values.firstWhere(
                  (d) => d.wireValue == v,
                ),
              );
            },
          ),
        ),
        if (waiting) ...[
          AlertBanner(
            tone: AlertTone.info,
            icon: 'clock',
            body:
                '대기 시간이 끝난 뒤에만 고를 수 있어요 · $minutes분 '
                '${seconds.toString().padLeft(2, '0')}초 남음',
          ),
          const SizedBox(height: 16),
        ],
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
    );
  }
}
