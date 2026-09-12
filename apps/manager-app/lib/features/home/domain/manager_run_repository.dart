import 'package:manager_app/features/home/data/models/manager_run.dart';

/// ManagerHome 화면이 보는 계약 — `presentation` 은 `ManagerRunApi`(data)를
/// 직접 보지 않는다(CONVENTIONS_FLUTTER.md §2).
// 메서드가 하나뿐이지만 `di.dart` 의 Provider<XRepository> 조립 지점과
// 맞추려 인터페이스로 둔다(CONVENTIONS_FLUTTER.md §2, RosterRepository 등
// 여러 메서드짜리와 같은 패턴) — 최상위 함수로 바꾸면 그 조립 방식이 깨진다.
// ignore: one_member_abstracts
abstract interface class ManagerRunRepository {
  /// §4.1. 실패하면 `dio_error_mapper` 를 거친 `Failure` 를 던진다.
  Future<List<ManagerRun>> fetchRuns({DateTime? date});
}
