import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/roster/domain/roster_repository.dart';
import 'package:manager_app/features/roster/presentation/roster_photo.dart';
import 'package:manager_app/features/roster/presentation/roster_providers.dart';

import '../../support/fake_token_storage.dart';

/// Ruling 377 — 학생 사진은 로그인 토큰이 있어야 받는다. 앱이 주소를 호스트에 붙이고
/// 토큰 헤더를 만들어 `StudentRow` 에 넘긴다.
void main() {
  const baseUrl = 'http://host:8080/api/v1';
  const auth = {'Authorization': 'Bearer tok-1'};

  group('resolveRosterPhoto', () {
    test('상대 경로는 호스트에 붙이고(/api/v1 중복 없음) 토큰 헤더를 싣는다', () {
      final photo = resolveRosterPhoto(
        '/api/v1/files/photos/a.jpg',
        baseUrl: baseUrl,
        authHeaders: auth,
      );

      expect(photo?.url, 'http://host:8080/api/v1/files/photos/a.jpg');
      expect(photo?.headers, auth);
    });

    test('옛 공개 절대 URL 은 그대로 두고 토큰을 싣지 않는다', () {
      final photo = resolveRosterPhoto(
        'https://cdn.example/s/1.jpg',
        baseUrl: baseUrl,
        authHeaders: auth,
      );

      expect(photo?.url, 'https://cdn.example/s/1.jpg');
      expect(photo?.headers, isNull);
    });

    test('null·빈 값이면 null(대체 아바타)', () {
      expect(
        resolveRosterPhoto(null, baseUrl: baseUrl, authHeaders: auth),
        isNull,
      );
      expect(
        resolveRosterPhoto('', baseUrl: baseUrl, authHeaders: auth),
        isNull,
      );
    });

    test('토큰을 아직 못 읽었으면 상대 경로는 null', () {
      expect(
        resolveRosterPhoto(
          '/api/v1/files/photos/a.jpg',
          baseUrl: baseUrl,
          authHeaders: null,
        ),
        isNull,
      );
    });
  });

  test('rosterPhotoHeadersProvider 는 저장된 access 토큰으로 Bearer 헤더를 만든다', () async {
    final container = ProviderContainer(
      overrides: [
        selectedRunIdProvider.overrideWith((ref) => 'run-1'),
        tokenStorageProvider.overrideWithValue(
          FakeTokenStorage(seedAccessToken: 'tok-9'),
        ),
        rosterRepositoryProvider.overrideWithValue(_EmptyRosterRepository()),
      ],
    );
    addTearDown(container.dispose);

    final headers = await container.read(rosterPhotoHeadersProvider.future);

    expect(headers, {'Authorization': 'Bearer tok-9'});
  });
}

class _EmptyRosterRepository implements RosterRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
