import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/domain/auth_repository.dart';
import 'package:parent_app/core/students/data/selected_student_storage.dart';

/// 로그아웃 호출만 받는 가짜 저장소 — 다른 메서드는 이 시험에서 불리면 안 된다.
class _StubAuthRepository implements AuthRepository {
  new({this.fail = false});

  final bool fail;

  @override
  Future<void> logout() async {
    if (fail) throw Exception('network down');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 로그아웃하면 기기에 기억해 둔 마지막 선택 자녀도 지워진다 — 같은 기기에서 다음 계정이 앞 계정의
/// 자녀 식별자를 물려받지 않는다.
void main() {
  late WidgetRef capturedRef;

  Future<void> pump(WidgetTester tester, {required bool failServer}) async {
    FlutterSecureStorage.setMockInitialValues({'selected_student_id': 's-1'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _StubAuthRepository(fail: failServer),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox();
          },
        ),
      ),
    );
  }

  testWidgets('로그아웃 뒤 저장된 선택 자녀 식별자를 읽으면 비어 있다', (tester) async {
    await pump(tester, failServer: false);
    expect(await SelectedStudentStorage().read(), 's-1');

    await signOut(capturedRef);

    expect(await SelectedStudentStorage().read(), isNull);
  });

  testWidgets('서버 호출이 실패해도 저장된 선택 자녀 식별자는 지워진다', (tester) async {
    await pump(tester, failServer: true);

    await expectLater(signOut(capturedRef), throwsException);

    expect(await SelectedStudentStorage().read(), isNull);
  });
}
