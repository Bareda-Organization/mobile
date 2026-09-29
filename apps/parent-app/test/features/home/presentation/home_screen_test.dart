import 'package:baraeda_core/baraeda_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/features/home/domain/notification_item.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/home/presentation/home_screen.dart';

/// 이월 항목 — `home_screen.dart` 가 알림 상대 시각 계산에 쓰는 시각을
/// `DateTime.now()` 직접 호출이 아니라 [clockProvider] 로 주입받는지
/// 확인한다(CONVENTIONS_FLUTTER.md §9). 고정 시각을 이 provider 로만
/// 넘겨 검증한다 — 프로덕션의 [SystemClock] 은 이 시험이 건드리지 않는다.
class _FixedClock implements Clock {
  const _FixedClock(this._value);

  final DateTime _value;

  @override
  DateTime now() => _value;
}

void main() {
  // 2026-09-29 사용자 지적 "한번 로그인 되면 로그아웃이 안 돼" — 로그아웃이 홈 맨 아래 [설정]
  // 안쪽 맨 아래에만 있어 찾지 못했다. 매니저 앱처럼 홈 머리말에 둔다(학부모·학생 공통).
  testWidgets('홈 머리말의 [로그아웃] 이 확인 대화를 연다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleCapabilitiesProvider.overrideWithValue(null),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          runsForStudentProvider.overrideWith(
            (ref, studentId) async => const <StudentRun>[],
          ),
          notificationsProvider.overrideWith(
            (ref) async => const NotificationPage(
              items: [],
              page: 1,
              size: 20,
              totalCount: 0,
              hasNext: false,
              unreadCount: 0,
            ),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(find.text('로그아웃 하시겠습니까?'), findsOneWidget);
  });

  testWidgets('알림 상대 시각은 DateTime.now() 가 아니라 주입된 시계를 따른다', (tester) async {
    final sentAt = DateTime(2026, 9, 12, 12);
    final fixedNow = sentAt.add(const Duration(minutes: 5));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 학생 갈래로 고정 — roleCapabilitiesProvider 가 null 이면
          // HomeScreen 이 _StudentSection 을 그린다.
          roleCapabilitiesProvider.overrideWithValue(null),
          myStudentIdProvider.overrideWith((ref) async => 's-1'),
          runsForStudentProvider.overrideWith(
            (ref, studentId) async => const <StudentRun>[],
          ),
          notificationsProvider.overrideWith(
            (ref) async => NotificationPage(
              items: [
                NotificationItem(
                  notificationId: 'n-1',
                  type: 'attendance',
                  title: '등원 완료',
                  body: '홍길동 학생이 등원했습니다',
                  sentAt: sentAt,
                  popup: false,
                  studentName: '홍길동',
                ),
              ],
              page: 1,
              size: 20,
              totalCount: 1,
              hasNext: false,
              unreadCount: 1,
            ),
          ),
          clockProvider.overrideWithValue(_FixedClock(fixedNow)),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('5분 전'), findsOneWidget);
  });
}
