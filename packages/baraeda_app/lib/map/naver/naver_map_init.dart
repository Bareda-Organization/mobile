import 'dart:async';

import 'package:flutter/foundation.dart';
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
/// **판단 근거 — 성공만 기억하는 이유**: 성공한 초기화는 그대로 돌려주지만, 실패한 초기화는 기억하지 않는다. 일시적인
/// 실패(인증 서버 응답 없음 등)가 앱을 다시 켤 때까지 모든 지도 화면을 막으면 안 되므로, 다음 지도 위젯이 다시 시도한다.
class NaverMapInit {
  new _();

  static Future<void>? _future;

  /// SDK 를 실제로 초기화하는 함수 — 시험이 바꿔 끼운다.
  @visibleForTesting
  static Future<void> Function({
    required String? clientId,
    required void Function(Object) onAuthFailed,
  })
  initializer = _initSdk;

  static Future<void> _initSdk({
    required String? clientId,
    required void Function(Object) onAuthFailed,
  }) => FlutterNaverMap().init(clientId: clientId, onAuthFailed: onAuthFailed);

  /// 시험 전용 — 기억한 초기화 결과를 지우고 SDK 초기화 함수를 되돌린다.
  @visibleForTesting
  static void resetForTest() {
    _future = null;
    initializer = _initSdk;
  }

  static final StreamController<Object> _authFailedController =
      StreamController<Object>.broadcast();

  /// SDK 가 인증 실패를 알려올 때마다 흘러나온다. 여러 `MapSurface` 인스턴스가
  /// 동시에 구독해도 된다(브로드캐스트).
  static Stream<Object> get onAuthFailed => _authFailedController.stream;

  /// 아직 시작 전이면 시작하고, 이미 시작했으면 그 Future 를 그대로 돌려준다. 시작이 실패하면 그 Future 를
  /// 기억하지 않아 다음 호출이 다시 시도한다. 호출부는 실패 시 `snapshot.hasError` 로 걸러 대체 화면을 그린다.
  static Future<void> ensureInitialized({required String? clientId}) {
    final started = _future ??= initializer(
      clientId: clientId,
      onAuthFailed: _authFailedController.add,
    );
    // 실패한 시도는 기억하지 않는다 — 같은 시도일 때만 지워, 그 사이 시작한 새 시도를 덮지 않는다.
    unawaited(
      started.catchError((Object _) {
        if (identical(_future, started)) _future = null;
      }),
    );
    return started;
  }
}
