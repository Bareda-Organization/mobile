/// 회차 관련 공통 값 — API_SPEC §4.1·§4.2·§4.6 의 `direction`·`run_status`·
/// 탑승 상태. ManagerHome · DriveMode · StopRoster 세 화면이 같은 값을 쓰므로
/// 화면마다 따로 정의하지 않고 `core/run` 에 둔다(`role_policy.dart` 가 권한
/// 판정을 한 곳에 모으는 것과 같은 이유로, 값 정의도 한 곳에 모은다).
library;

/// API_SPEC §4.1 `direction`.
enum RunDirection {
  /// 등원.
  toAcademy('to_academy'),

  /// 하원.
  fromAcademy('from_academy');

  const RunDirection(this.wireValue);

  final String wireValue;

  static RunDirection? fromWireValueOrNull(String? value) {
    for (final direction in RunDirection.values) {
      if (direction.wireValue == value) return direction;
    }
    return null;
  }
}

/// API_SPEC §4.1 `run_status` — §4.10 종료 전이가 이 값을 `finished` 로
/// 옮기는 유일한 방법이다(전용 종료 API 부재).
enum RunStatus {
  idle('idle'),
  confirmed('confirmed'),
  moving('moving'),
  finished('finished');

  const RunStatus(this.wireValue);

  final String wireValue;

  static RunStatus? fromWireValueOrNull(String? value) {
    for (final status in RunStatus.values) {
      if (status.wireValue == value) return status;
    }
    return null;
  }
}

/// API_SPEC §4.2 `stops[].students[].status` · §4.6 `status`.
/// `absent` 는 `change=removed` 행에서만 등장한다 — 버스 간 이동으로 빠진
/// 학생을 명단에서 지우지 않고 빨강으로 남긴다(RTE-04 · Ruling 341 ·
/// BR-016). 처리 대상이 아니며 `absent_n` 에 세지 않는다.
enum RiderStatus {
  waiting('waiting'),
  boarded('boarded'),
  alighted('alighted'),
  noShow('no_show'),
  absent('absent');

  const RiderStatus(this.wireValue);

  final String wireValue;

  static RiderStatus? fromWireValueOrNull(String? value) {
    for (final status in RiderStatus.values) {
      if (status.wireValue == value) return status;
    }
    return null;
  }
}
