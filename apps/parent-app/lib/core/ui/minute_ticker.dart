import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';

/// 남은 시간 문구를 1분마다 다시 그리는 자리 — 분 단위 카운트다운(`FEATURE_SPEC P-03`)이
/// 화면을 열어 둔 채로도 줄어든다.
///
/// 시각은 위젯이 직접 재지 않고 `clockProvider` 에서 받아 [builder] 에 넘긴다
/// (`CONVENTIONS_FLUTTER §9`).
class MinuteTicker extends ConsumerStatefulWidget {
  const new({required this.builder, super.key});

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  ConsumerState<MinuteTicker> createState() => _MinuteTickerState();
}

class _MinuteTickerState extends ConsumerState<MinuteTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, ref.watch(clockProvider).now());
}
