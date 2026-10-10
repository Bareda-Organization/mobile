import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/app.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/features/auth/presentation/login_screen.dart';

import '../../support/fake_token_storage.dart';

/// 모든 요청에 `401` 을 돌려주는 어댑터 — access 도 refresh 도 거절된 상황.
class _RejectAllAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"error":{"code":"TOKEN_EXPIRED","message":"m"}}',
    401,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

/// R52 낮음 A7 — 저장된 로그인이 앱을 켜는 순간 거절되면, 로그인 화면이 "로그인이 만료됐어요" 를 보여야 한다.
/// 만료 신호는 부팅(`authBootstrapProvider`) 중에 나가는데, 그 신호를 받는 구독은 라우터가 만들어질 때야 생겼다.
void main() {
  testWidgets('앱을 켤 때 저장된 토큰이 거절되면 로그인 화면에 만료 안내가 뜬다', (tester) async {
    final tokens = FakeTokenStorage(
      seedRefreshToken: 'r',
      seedAccessToken: 'a',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokens),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(
              tokenStorage: tokens,
              baseUrl: 'https://example.invalid',
              dio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
                ..httpClientAdapter = _RejectAllAdapter(),
              refreshDio: Dio(BaseOptions(baseUrl: 'https://example.invalid'))
                ..httpClientAdapter = _RejectAllAdapter(),
            ),
          ),
        ],
        child: const BaraedaParentApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('로그인이 만료됐어요. 다시 로그인해 주세요.'), findsOneWidget);
  });

  testWidgets('저장된 토큰이 없으면 안내 없이 로그인 화면만 뜬다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
        ],
        child: const BaraedaParentApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.textContaining('로그인이 만료됐어요'), findsNothing);
  });
}
