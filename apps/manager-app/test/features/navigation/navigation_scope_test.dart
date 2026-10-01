import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/features/navigation/data/models/navigation_scope.dart';
import 'package:manager_app/features/navigation/data/navigation_api.dart';

/// 서버처럼 `scope` 에 따라 다르게 답하는 가짜 어댑터 — 받은 요청을 기록한다.
/// `next` 는 경유지 없이 다음 목적지 1곳, `remaining` 은 경유지 1곳 + 최종 목적지(API_SPEC §4.16).
class _ScopeAwareAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final isNext = options.queryParameters['scope'] == 'next';
    final body = {
      'data': {
        'provider': 'kakao',
        'waypoints': isNext
            ? <Object>[]
            : [
                {'lat': 37.51, 'lng': 127.01, 'name': '1번', 'stop_id': 's1'},
              ],
        'destination': isNext
            ? {'lat': 37.51, 'lng': 127.01, 'name': '1번', 'stop_id': 's1'}
            : {'lat': 37.53, 'lng': 127.03, 'name': '학원', 'stop_id': 's9'},
        'truncated': false,
        'total_remaining_stops': 2,
      },
    };
    return ResponseBody.fromString(
      jsonEncode(body['data']),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  group('NavigationApi.fetch — scope 쿼리 (API_SPEC §4.16)', () {
    for (final scope in NavigationScope.values) {
      test('${scope.name} 를 고르면 서버에 scope=${scope.name} 으로 묻는다', () async {
        final adapter = _ScopeAwareAdapter();
        final api = NavigationApi(
          dio: Dio(BaseOptions(baseUrl: 'http://x/api/v1'))
            ..httpClientAdapter = adapter,
        );

        final route = await api.fetch('run-1', scope);

        expect(adapter.requests.single.path, '/runs/run-1/navigation');
        expect(adapter.requests.single.queryParameters, {'scope': scope.name});
        // 응답이 범위에 맞게 읽힌다 — next 는 경유지 없이 목적지 하나.
        expect(route.waypoints.length, scope == NavigationScope.next ? 0 : 1);
      });
    }
  });
}
