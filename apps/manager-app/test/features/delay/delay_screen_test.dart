import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:manager_app/app/di.dart';
import 'package:manager_app/core/auth/auth_providers.dart';
import 'package:manager_app/core/auth/role_policy.dart';
import 'package:manager_app/core/auth/user_role.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/delay/data/models/delay_request.dart';
import 'package:manager_app/features/delay/data/models/delay_result.dart';
import 'package:manager_app/features/delay/domain/delay_repository.dart';
import 'package:manager_app/features/delay/presentation/delay_screen.dart';

/// 테스트 전용 대역 — 실제 네트워크 대신 호출 여부·인자만 기록한다.
class _FakeDelayRepository implements DelayRepository {
  _FakeDelayRepository({this.result, this.failure});

  final DelayResult? result;
  final Failure? failure;
  DelayRequest? lastRequest;
  String? lastRunId;

  @override
  Future<DelayResult> sendDelay({
    required String runId,
    required DelayRequest request,
  }) async {
    lastRunId = runId;
    lastRequest = request;
    // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다
    // (baraeda_core/error/failure.dart 참고) — guard.dart 와 같은 예외.
    // ignore: only_throw_errors
    if (failure != null) throw failure!;
    return result!;
  }
}

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

void main() {
  const runId = 'run-1';

  testWidgets('선택된 운행이 없으면 안내만 보여준다', (tester) async {
    await tester.pumpWidget(
      _wrap(const DelayScreen(), [
        selectedRunIdProvider.overrideWith((ref) => null),
      ]),
    );

    expect(find.text('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'), findsOneWidget);
  });

  testWidgets('기사 역할이면 전송 폼 대신 권한 안내만 보여준다 (canSendDelayNotification=false)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const DelayScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        roleCapabilitiesProvider.overrideWithValue(
          RoleCapabilities.of(UserRole.driver),
        ),
      ]),
    );

    expect(find.text('동승자만 지연 알림을 보낼 수 있습니다'), findsOneWidget);
    expect(find.text('지연 알림 보내기'), findsNothing);
  });

  testWidgets('동승자 역할이면 전송 후 알림 대상 요약을 보여준다', (tester) async {
    final fakeRepo = _FakeDelayRepository(
      result: const DelayResult(
        notifiedGuardians: true,
        notifiedStudents: false,
        notifiedStaff: true,
      ),
    );

    await tester.pumpWidget(
      _wrap(const DelayScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        roleCapabilitiesProvider.overrideWithValue(
          RoleCapabilities.of(UserRole.escort),
        ),
        delayRepositoryProvider.overrideWithValue(fakeRepo),
      ]),
    );

    expect(find.text('지연 알림 보내기'), findsOneWidget);

    await tester.tap(find.text('지연 알림 보내기'));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastRunId, runId);
    expect(fakeRepo.lastRequest?.minutes, 5);
    expect(fakeRepo.lastRequest?.reason, DelayReason.traffic);
    expect(find.text('보호자 · 직원에게 알림을 보냈습니다'), findsOneWidget);
  });

  group('보내기 전 문구 미리보기 (R46, B2 #26)', () {
    Future<void> pumpEscort(WidgetTester tester) => tester.pumpWidget(
      _wrap(const DelayScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        roleCapabilitiesProvider.overrideWithValue(
          RoleCapabilities.of(UserRole.escort),
        ),
        delayRepositoryProvider.overrideWithValue(
          _FakeDelayRepository(
            result: const DelayResult(
              notifiedGuardians: true,
              notifiedStudents: true,
              notifiedStaff: true,
            ),
          ),
        ),
      ]),
    );

    testWidgets('안내 문구를 비우면 자동 문구가 나간다고 알리고 사유·분을 따라간다', (tester) async {
      await pumpEscort(tester);

      expect(
        find.text(
          '안내 문구를 비우면 자동 문구가 나갑니다 — '
          '"교통 체증" 사유와 "현재 예상 지연 5분" 이 들어갑니다',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('기상 악화'));
      await tester.pump();

      expect(find.textContaining('"기상 악화" 사유'), findsOneWidget);
    });

    testWidgets('문구를 입력하면 학부모·학생에게 나갈 문장을 그대로 보여준다', (tester) async {
      await pumpEscort(tester);

      await tester.enterText(find.byType(TextField), '10분 정도 늦습니다');
      await tester.pump();

      expect(
        find.text('학부모·학생에게 이렇게 나갑니다 — "○○ 학생이 탄 버스 — 10분 정도 늦습니다"'),
        findsOneWidget,
      );
      expect(find.textContaining('자동 문구가 나갑니다'), findsNothing);
    });
  });

  testWidgets('전송 실패 시 서버 실패 사유를 보여준다', (tester) async {
    final fakeRepo = _FakeDelayRepository(
      failure: const ApiFailure(
        statusCode: 409,
        code: 'DELAY_DUPLICATE',
        message: '중복',
      ),
    );

    await tester.pumpWidget(
      _wrap(const DelayScreen(), [
        selectedRunIdProvider.overrideWith((ref) => runId),
        roleCapabilitiesProvider.overrideWithValue(
          RoleCapabilities.of(UserRole.escort),
        ),
        delayRepositoryProvider.overrideWithValue(fakeRepo),
      ]),
    );

    await tester.tap(find.text('지연 알림 보내기'));
    await tester.pumpAndSettle();

    expect(find.text('직전과 같은 지연 알림은 다시 보낼 수 없습니다'), findsOneWidget);
  });
}
