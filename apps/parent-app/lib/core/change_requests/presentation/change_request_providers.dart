import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/change_requests/domain/change_request.dart';

/// §3.9 — 학생별 일일 변경 신청 이력 + 대기 건수(`pending_count`).
/// `schedule`(신청 이력 화면) · `home`(처리 대기 건수 배지, P-06 — "홈에
/// 처리 대기 건수 배지") 두 feature 가 함께 쓰므로 `core/` 에 둔다
/// (CONVENTIONS_FLUTTER.md §2, `core/runs/presentation/run_providers.dart`
/// 와 같은 이유).
// ignore: specify_nonobvious_property_types
final changeRequestsProvider =
    FutureProvider.family<ChangeRequestPage, String>((ref, studentId) {
      final repository = ref.watch(changeRequestRepositoryProvider);
      return repository.getChangeRequests(studentId);
    });
