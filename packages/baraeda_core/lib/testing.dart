/// 시험 전용 도우미 — 앱 · 패키지 시험이 파일마다 복사해 쓰던 대역을 한 곳에 둔다.
/// 제품 코드는 가져오지 않는다(`baraeda_core.dart` 배럴에 넣지 않는다).
library;

import 'dart:async';

import 'package:baraeda_core/error/failure.dart';
import 'package:baraeda_core/notifications/notification_item.dart';
import 'package:baraeda_core/notifications/notification_repository.dart';
import 'package:baraeda_core/storage/token_storage.dart';
import 'package:baraeda_core/time/clock.dart';

/// 정해 둔 시각만 알려 주는 [Clock] — [current] 를 바꾸면 시간이 흐른 것처럼 쓴다.
class FixedClock implements Clock {
  /// [current] 로 시작한다.
  new(this.current);

  /// [now] 가 돌려주는 시각.
  DateTime current;

  @override
  DateTime now() => current;
}

/// access 토큰 읽기가 끝내 응답하지 않는 [TokenStorage] — 운행 채널(WebSocket)이 연결을 시작하지 못하게
/// 붙잡아 두는 시험용이다. 플랫폼 보안 저장소를 건드리지 않는다.
class NeverResolvingTokenStorage extends TokenStorage {
  /// 저장 키는 시험이 쓰지 않는 값이다.
  new()
    : super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  @override
  Future<String?> readAccessToken() => Completer<String?>().future;

  /// 로그인 기록은 없는 기기다 — 바로 `null`.
  @override
  Future<String?> readRefreshToken() async => null;
}

/// 실서버 계약 시험이 붙을 주소. **주소를 받지 못하면 던진다.**
///
/// 기본값으로 조용히 `localhost:8080`(조율자의 시드 서버)에 붙는 경로를 없애는 것이 이 함수의 전부다 —
/// `--dart-define=API_BASE_URL` 을 빠뜨린 실행이 시드 DB 에 실제 레코드를 만든 일이 있다. 안내 문구가 아니라
/// 구조로 막는다. 백엔드 없이 나머지 시험만 돌리려면 `flutter test --exclude-tags real_backend`.
String requireRealBackendBaseUrl() {
  if (!const bool.hasEnvironment('API_BASE_URL')) {
    throw StateError(
      '실서버 계약 시험에는 대상 주소가 필요하다. '
      'flutter test --dart-define=API_BASE_URL=http://localhost:<전용포트>/api/v1 로 실행하라. '
      '주소를 생략하면 기본값 8080(조율자 시드 서버)으로 실제 요청이 나간다. '
      '백엔드 없이 돌리려면 --exclude-tags real_backend 를 쓴다.',
    );
  }
  return const String.fromEnvironment('API_BASE_URL');
}

/// `TokenStorage` 의 시험용 대역 — `flutter_secure_storage` 의 플랫폼
/// 채널을 타지 않고 메모리에만 저장한다.
///
/// `flutter_test` 환경에는 시크릿 스토리지 플랫폼 채널이 물려 있지 않다 —
/// 실제 `TokenStorage`(기본 `FlutterSecureStorage`)를 그대로 쓰면
/// `authBootstrapProvider` 의 `readRefreshToken()` 호출이 응답 없는 채널
/// 요청에 걸려 `pumpAndSettle` 이 시간 초과한다. 생성자로 넘긴
/// `seedRefreshToken` 으로 "이미 로그인된 채 앱을 다시 켠 상태"(목표 표
/// 5항 자동 로그인)도 같은 대역으로 시험한다.
class FakeTokenStorage extends TokenStorage {
  /// [seedRefreshToken] · [seedAccessToken] 이 있으면 이미 로그인된 기기로 시작한다.
  new({String? seedRefreshToken, String? seedAccessToken})
    : _refreshToken = seedRefreshToken,
      _accessToken = seedAccessToken,
      super(
        accessTokenKey: 'test_access_token',
        refreshTokenKey: 'test_refresh_token',
      );

  String? _accessToken;
  String? _refreshToken;

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
  }
}

/// 서버처럼 걸러 보기·쪽 나누기·읽음 처리를 흉내 내고, 받은 요청을 기록하는 가짜.
///
/// `unread_count` 는 서버처럼 걸러 보기와 무관하게 **전체** 안 읽은 수다(§3.12).
class FakeNotificationRepository implements NotificationRepository {
  /// [items] 로 시작한다 — 서버가 가진 전체 알림이다.
  new(List<NotificationItem> items) : _items = [...items];

  List<NotificationItem> _items;

  /// 받은 목록 요청(쪽 · 크기 · 안 읽음만).
  final requests = <({int page, int size, bool unreadOnly})>[];

  /// 읽음 처리 요청을 받은 알림 id.
  final marked = <String>[];

  /// 채워 두면 [getNotifications] 가 던진다. 특정 쪽에서만 던지려면 [failOnPage].
  Failure? getFailure;

  /// [getFailure] 를 이 쪽에서만 던진다 — `null` 이면 모든 쪽.
  int? failOnPage;

  /// 채워 두면 [markRead] 가 던진다.
  Failure? markFailure;

  /// 서버가 센 전체 안 읽은 수.
  int get unreadCount => _items.where((item) => item.isUnread).length;

  @override
  Future<NotificationPage> getNotifications({
    int page = 0,
    int size = 20,
    bool unreadOnly = false,
  }) async {
    requests.add((page: page, size: size, unreadOnly: unreadOnly));
    if (getFailure != null && (failOnPage == null || failOnPage == page)) {
      // Failure 는 Exception/Error 를 상속하지 않는다 — 리포지토리가 던지는 형태 그대로.
      // ignore: only_throw_errors
      throw getFailure!;
    }
    final matched = unreadOnly
        ? _items.where((item) => item.isUnread).toList()
        : _items;
    final from = page * size;
    final slice = matched.skip(from).take(size).toList();
    return NotificationPage(
      items: slice,
      page: page,
      size: size,
      totalCount: matched.length,
      hasNext: from + slice.length < matched.length,
      unreadCount: unreadCount,
    );
  }

  @override
  Future<void> markRead(String notificationId) async {
    // 위와 같은 이유.
    // ignore: only_throw_errors
    if (markFailure != null) throw markFailure!;
    marked.add(notificationId);
    _items = [
      for (final item in _items)
        if (item.notificationId == notificationId && item.isUnread)
          item.markedRead(DateTime.utc(2026, 9, 30, 1))
        else
          item,
    ];
  }
}
