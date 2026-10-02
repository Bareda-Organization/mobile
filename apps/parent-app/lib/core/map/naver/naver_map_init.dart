import 'dart:async';

import 'package:flutter_naver_map/flutter_naver_map.dart';

/// `FlutterNaverMap().init()` 을 앱 전체에서 딱 한 번만 부르게 감싼 것.
///
/// **판단 근거 — 왜 필요한가**: SDK 의 `init()` 은 전역 싱글턴
/// (`FlutterNaverMap.isInitialized`)이라 두 번째 호출은 무의미하고,
/// `onAuthFailed` 콜백도 하나만 등록된다(1.4.4 소스 확인 —
/// `flutter_naver_map_initializer.dart`). 그런데 `MapSurface` 는 화면마다
/// 새 인스턴스로 만들어질 수 있으므로, 각 인스턴스가 저마다 인증 실패를
/// 구독할 수 있어야 한다 — 그래서 콜백 하나를 브로드캐스트 스트림으로
/// 한 번 더 감싼다.
///
/// **판단 근거 — 실패한 Future 를 그대로 기억하는 이유**: 위젯 시험
/// 환경에는 플랫폼 채널이 없어 `invokeMethod` 가 `MissingPluginException`
/// 으로 거절된다. 이 초기화 결과를 캐시하지 않고 매번 새로 시도하면
/// 재시도 정책까지 이 라운드에서 설계해야 하는데, 그건 2단계(성능·재시도
/// 튜닝) 몫이라 범위 밖이다 — 이번 라운드는 "한 번 실패하면 그 세션에서는
/// 계속 실패로 본다"는 가장 단순한 규칙만 둔다.
class NaverMapInit {
  new _();

  static Future<void>? _future;

  static final StreamController<Object> _authFailedController =
      StreamController<Object>.broadcast();

  /// SDK 가 인증 실패를 알려올 때마다 흘러나온다. 여러 `MapSurface` 인스턴스가
  /// 동시에 구독해도 된다(브로드캐스트).
  static Stream<Object> get onAuthFailed => _authFailedController.stream;

  /// 아직 시작 전이면 시작하고, 이미 시작했으면(성공이든 실패든) 그 Future 를
  /// 그대로 돌려준다. 호출부는 실패 시 `snapshot.hasError` 로 걸러 대체
  /// 화면을 그리면 된다 — 이 클래스는 재시도하지 않는다.
  static Future<void> ensureInitialized({required String? clientId}) {
    return _future ??= FlutterNaverMap().init(
      clientId: clientId,
      onAuthFailed: _authFailedController.add,
    );
  }
}
