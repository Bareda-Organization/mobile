import 'dart:convert';
import 'dart:typed_data';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_core/testing.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/academy_contact.dart';
import 'package:parent_app/features/auth/presentation/blocked_screen.dart';


class _MemoryContactStorage extends AcademyContactStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> save(String contact) async => value = contact;
}

/// 저장할 때마다 예외를 던지는 문의처 저장소 — 저장 실패가 `/me` 를 막지 않는지 본다.
class _ThrowingContactStorage extends AcademyContactStorage {
  @override
  Future<void> save(String contact) async {
    throw StateError('저장소 쓰기 실패');
  }
}

/// `/me` 에 정해 둔 `academy.contact` 로 답하는 가짜 어댑터.
class _MeAdapter implements HttpClientAdapter {
  new(this.contact);

  final String? contact;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({
      'account_id': 'a-1',
      'login_id': 'parent1',
      'name': '학부모',
      'phone': '010-0000-0000',
      'role': 'parent',
      'status': 'active',
      'academy': {'id': 'ac-1', 'name': '하늘학원', 'contact': ?contact},
    }),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

/// R53 t3 A4 — 학원 문의처를 승인 대기 화면에서만 저장해, 대기 화면을 거치지 않은 계정은 차단 화면 전화와
/// 홈 실패 전화 카드가 없었다. `/me` 가 성공할 때마다 저장한다.
void main() {
  late _MemoryContactStorage storage;

  ProviderContainer containerWith(
    String? contact, {
    AcademyContactStorage? contactStorage,
  }) {
    storage = _MemoryContactStorage();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = _MeAdapter(contact);
    final container = ProviderContainer(
      overrides: [
        academyContactStorageProvider.overrideWithValue(
          contactStorage ?? storage,
        ),
        authApiProvider.overrideWithValue(
          AuthApi(dio: dio, tokenStorage: FakeTokenStorage()),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('/me 가 성공하면 학원 문의처를 기기에 저장한다', () async {
    final container = containerWith('하늘학원 032-000-1100');

    await container.read(authRepositoryProvider).me();

    expect(storage.value, '하늘학원 032-000-1100');
  });

  test('/me 에 문의처가 없으면 이미 저장한 문의처를 지우지 않는다', () async {
    final container = containerWith(null);
    storage.value = '전에 저장한 032-000-1100';

    await container.read(authRepositoryProvider).me();

    expect(storage.value, '전에 저장한 032-000-1100');
  });

  test('문의처가 공백뿐이면 이미 저장한 문의처를 지우지 않는다', () async {
    final container = containerWith('   ');
    storage.value = '전에 저장한 032-000-1100';

    await container.read(authRepositoryProvider).me();

    expect(storage.value, '전에 저장한 032-000-1100');
  });

  test('문의처 저장이 예외를 던져도 /me 는 성공한다', () async {
    final container = containerWith(
      '하늘학원 032-000-1100',
      contactStorage: _ThrowingContactStorage(),
    );

    final me = await container.read(authRepositoryProvider).me();

    expect(me.accountId, 'a-1');
  });

  testWidgets('/me 로 저장한 문의처가 차단 화면의 전화 단추가 된다', (tester) async {
    final container = containerWith('하늘학원 032-000-1100');
    await tester.runAsync(container.read(authRepositoryProvider).me);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BlockedScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('학원에 전화 · 032-000-1100'), findsOneWidget);
  });
}
