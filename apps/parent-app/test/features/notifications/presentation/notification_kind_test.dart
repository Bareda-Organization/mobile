import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/features/notifications/presentation/notification_kind.dart';

/// 학부모·학생 앱에 도달하는 알림 종류(`API_SPEC §9.7` 수신자 열) — 폐지 2종(승·하차 취소)은 과거 발송분 보존용.
const _reachable = [
  'boarding',
  'alighting',
  'arrive',
  'no_show',
  'delay',
  'run_started',
  'change_decided',
  'signup_decided',
  'route_changed',
  'emergency',
  'emergency_canceled',
];

void main() {
  test('종류마다 아이콘 모양이 다르다 — 색만으로 가르지 않는다', () {
    final icons = [for (final type in _reachable) kindOf(type).icon];

    expect(icons.toSet().length, icons.length, reason: icons.join(', '));
  });

  test('중요 통지는 지연 · 미승차 · 노선 변경 3종뿐이다(NTF-10)', () {
    final important = [
      for (final type in _reachable)
        if (kindOf(type).important) type,
    ];

    expect(important, unorderedEquals(['no_show', 'delay', 'route_changed']));
  });

  test('미승차·비상은 경고 색, 승·하차는 초록이다', () {
    expect(kindOf('no_show').status, BaraedaStatus.missed);
    expect(kindOf('emergency').status, BaraedaStatus.missed);
    expect(kindOf('boarding').status, BaraedaStatus.boarded);
    expect(kindOf('alighting').status, BaraedaStatus.boarded);
    expect(kindOf('delay').status, BaraedaStatus.moving);
  });

  // §9.7 은 앞으로도 늘어난다 — 모르는 종류가 초록 '승차' 로 떨어지면 미승차 사고가 정상으로 읽힌다(2026-09-21 실측).
  test('모르는 종류는 중립 · 중요 아님으로 떨어진다', () {
    final kind = kindOf('some_new_type');

    expect(kind.status, BaraedaStatus.idle);
    expect(kind.important, isFalse);
    expect(kind.label, '안내');
  });

  test('눌렀을 때 갈 화면 — 운행 관련은 실시간 지도 · 변경 결과는 일정', () {
    for (final type in [
      'boarding',
      'alighting',
      'no_show',
      'arrive',
      'delay',
      'run_started',
      'route_changed',
    ]) {
      expect(kindOf(type).route, AppRoutes.liveMap, reason: type);
    }
    expect(kindOf('change_decided').route, AppRoutes.schedule);
    expect(kindOf('signup_decided').route, isNull);
  });

  test('낭독용 종류 이름', () {
    expect(kindOf('no_show').label, '미승차');
    expect(kindOf('arrive').label, '곧 도착');
    expect(kindOf('boarding').label, '승차');
    expect(kindOf('alighting').label, '하차');
  });
}
