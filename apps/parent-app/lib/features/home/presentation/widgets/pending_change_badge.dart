import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/core/change_requests/presentation/change_request_providers.dart';

/// P-06 "홈에 처리 대기 건수 배지" — §3.9 `pending_count` 가 0보다 크면
/// 눌러서 §4.8 신청 이력(schedule 화면)으로 이동한다. 로딩·에러는 이
/// 화면의 본체(회차 목록)를 가리지 않도록 조용히 넘어간다 — 배지는 부가
/// 정보라 실패해도 홈 화면 자체를 막을 이유가 없다.
class PendingChangeBadge extends ConsumerWidget {
  const new({required this.studentId, super.key});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(changeRequestsProvider(studentId));

    return pageAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (page) {
        if (page.pendingCount <= 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: BaraedaSpacing.space4),
          // R32 P15 — 화면 읽기 프로그램에는 "처리 대기 · 2" 대신 "처리 대기 2건" 으로 읽힌다.
          child: Semantics(
            button: true,
            label: '처리 대기 ${page.pendingCount}건',
            excludeSemantics: true,
            onTap: () => context.push(AppRoutes.schedule),
            child: GestureDetector(
              onTap: () => context.push(AppRoutes.schedule),
              child: Align(
                alignment: Alignment.centerLeft,
                child: BaraedaBadge(
                  label: '처리 대기',
                  tone: BaraedaBadgeTone.amber,
                  count: page.pendingCount,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
