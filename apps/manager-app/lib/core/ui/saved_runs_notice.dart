import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/time/run_time_labels.dart';

/// 통신이 끊겨 기기 저장본으로 오늘 회차 목록을 보는 동안 띄우는 안내(NFR-01) — 홈 · 운행 준비 · 명단 ·
/// 비상 화면이 같은 문구를 쓴다.
class SavedRunsNotice extends StatelessWidget {
  /// [savedAt] 은 저장본을 서버에서 받은 시각이다.
  const new({required this.savedAt, super.key});

  final DateTime savedAt;

  @override
  Widget build(BuildContext context) {
    return AlertBanner(
      tone: AlertTone.missed,
      title: '저장해 둔 목록으로 보고 있어요',
      body: '서버에 연결하지 못해 ${hhmm(savedAt)}에 받은 목록을 보여 줘요 · 연결되면 자동으로 다시 불러와요',
    );
  }
}

/// 오늘 회차 목록이 저장본일 때만 [SavedRunsNotice] 를 그리고, 서버에서 새로 받았으면 아무것도 그리지 않는다.
class SavedRunsBanner extends ConsumerWidget {
  /// 화면 맨 위 목록 바깥에 둔다.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAt = ref.watch(savedRunsAtProvider);
    if (savedAt == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SavedRunsNotice(savedAt: savedAt),
    );
  }
}
