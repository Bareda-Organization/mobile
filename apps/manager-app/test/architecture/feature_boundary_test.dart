import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 기능끼리의 import 와 `presentation → data` import 를 막는 검사
/// (`CONVENTIONS_FLUTTER.md §2`, Ruling 938 B).
///
/// **판단 근거** — 화면이 `data/` 의 DTO 를 직접 물면 API 모양이 바뀔 때 화면까지 고쳐야 하고,
/// 한 기능이 다른 기능의 파일을 물면 그 파일을 옮길 때 두 화면이 함께 깨진다.
///
/// 기능 사이 import 는 이미 많아(운행 → 명단 → 오프라인 큐가 한 흐름이다) 한 번에 걷지 못한다.
/// 그래서 지금 있는 쌍을 [_allowedCrossFeature] 에 고정한다 — 새 쌍이 생기면 실패하고, 목록의 쌍이
/// 더는 없어도 실패한다(목록은 줄어들기만 한다).
void main() {
  final features = Directory('${Directory.current.path}/lib/features');
  final imports = RegExp(
    r'''import\s+['"]package:manager_app/(features/(\w+)/(\w+)/[^'"]*|[^'"]*)['"]''',
  );

  List<({String file, String own, String? target, String? layer})> all() => [
    for (final entity in features.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart'))
        for (final match in imports.allMatches(entity.readAsStringSync()))
          (
            file: entity.path.split('/lib/features/').last,
            own: entity.path.split('/lib/features/').last.split('/').first,
            target: match.group(2),
            layer: match.group(3),
          ),
  ];

  test('presentation 의 파일이 data 를 import 하지 않는다', () {
    expect(features.existsSync(), isTrue, reason: 'lib/features 를 찾을 수 없다');

    final violations = [
      for (final i in all())
        if (i.file.contains('/presentation/') && i.layer == 'data')
          '${i.file} → ${i.target}/data',
    ];

    expect(
      violations,
      isEmpty,
      reason:
          '화면은 data 를 거치지 않고 domain 의 모델·인터페이스를 쓴다: '
          '${violations.join(', ')}',
    );
  });

  test('기능 사이 import 는 고정한 목록 안의 쌍뿐이다', () {
    final found = {
      for (final i in all())
        if (i.target != null && i.target != i.own) '${i.own} -> ${i.target}',
    };

    final added = found.difference(_allowedCrossFeature.keys.toSet());
    final gone = _allowedCrossFeature.keys.toSet().difference(found);

    expect(added, isEmpty, reason: '새 기능 간 import — 공유 값은 core/ 로 올린다: $added');
    expect(gone, isEmpty, reason: '없어진 쌍은 목록에서 지운다: $gone');
  });
}

/// 지금 있는 기능 간 import 쌍과 그 이유 — 줄이기만 하고 늘리지 않는다.
const _allowedCrossFeature = <String, String>{
  'delay -> roster': '지연 화면이 현재 운행의 명단 상태(roster_providers)를 읽는다',
  'drive_mode -> home':
      '운행 화면이 오늘 운행 목록·현재 운행(home_providers · ManagerRun)을 쓴다',
  'drive_mode -> navigation':
      '운행 화면이 외부 내비 열기(open_navigation · NavigationScope)를 쓴다',
  'drive_mode -> offline_queue':
      '도착 처리를 오프라인 큐로 보낸다(repository · SendOutcome · providers)',
  'drive_mode -> position':
      '운행 중 위치 송신(position_transmitter · position_link)을 켠다',
  'drive_mode -> roster': '정차지 카드가 명단(RosterResponse)과 변경 확인 배너를 보인다',
  'drive_mode -> route_map': '운행 화면이 노선 지도 데이터(route_providers)를 쓴다',
  'emergency -> home': '비상 신고가 현재 운행(ManagerRun · home_providers)에 묶인다',
  'emergency -> offline_queue': '비상 신고를 오프라인 큐로 보내고 미전송 요약을 보인다',
  'emergency -> roster': '비상 신고가 명단 상태(roster_providers)를 읽는다',
  'home -> drive_mode': '홈이 운행 중 상태(drive_mode_providers)를 읽어 이어 하기를 보인다',
  'home -> navigation': '홈의 운행 준비 화면이 외부 내비를 연다',
  'home -> offline_queue': '홈이 미전송 건수(offline_queue_providers)를 보인다',
  'home -> roster': '운행 준비 화면이 명단(RosterResponse)과 변경 확인 배너를 쓴다',
  'home -> route_map': '운행 준비 화면이 노선(route_providers · RouteResponse)을 쓴다',
  'offline_queue -> emergency': '미전송 요약이 비상 신고 종류(EmergencyType)를 이름으로 보인다',
  'offline_queue -> roster':
      '큐 재전송이 명단 캐시(roster_cipher · roster_providers)를 갱신한다',
  'position -> home': '위치 송신이 현재 운행(home_providers)을 읽는다',
  'roster -> home': '명단 화면이 현재 운행(ManagerRun · home_providers)을 읽는다',
  'roster -> offline_queue':
      '승하차 변경을 오프라인 큐로 보낸다(repository · database · SendOutcome)',
  'route_map -> emergency': '노선 지도 화면에 비상 신고 단추(emergency_button)를 둔다',
  'route_map -> position': '노선 지도가 위치 송신(position_transmitter)을 쓴다',
  'run_end -> drive_mode': '운행 종료 화면이 마지막 도착 결과(ArriveStopResult)를 받는다',
  'run_end -> home': '운행 종료 화면이 현재 운행(ManagerRun)을 쓴다',
  'run_end -> offline_queue': '종료 보고를 오프라인 큐로 보낸다(repository · SendOutcome)',
  'run_end -> position': '운행 종료 때 위치 송신을 멈춘다(position_transmitter)',
  'run_end -> roster': '운행 종료 화면이 명단(RosterResponse · roster_providers)을 읽는다',
};
