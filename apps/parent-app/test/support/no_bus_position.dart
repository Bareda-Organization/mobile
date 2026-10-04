import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:parent_app/app/di.dart';
import 'package:parent_app/features/live_map/domain/bus_position.dart';
import 'package:parent_app/features/live_map/domain/bus_position_repository.dart';

/// 오늘 회차가 없다는(`404 RUN_NOT_FOUND`) §3.11 대역 — 홈 지도 미리보기가 서버를 부르는 시험이 아닌 곳에서,
/// 진짜 네트워크를 기다리며 로딩 뼈대(끝없이 깜빡임)가 남아 `pumpAndSettle` 이 끝나지 않는 일을 막는다.
class _NoRunPositionRepository implements BusPositionRepository {
  const _NoRunPositionRepository();

  @override
  Future<BusPosition> getBusPosition(String studentId) => Future.error(
    const Failure.api(
      statusCode: 404,
      code: 'RUN_NOT_FOUND',
      message: '오늘 회차가 없습니다',
    ),
  );
}

final Override noBusPositionOverride = busPositionRepositoryProvider
    .overrideWithValue(const _NoRunPositionRepository());
