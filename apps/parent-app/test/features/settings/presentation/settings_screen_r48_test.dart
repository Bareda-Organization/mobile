import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/features/settings/domain/notification_settings.dart';
import 'package:parent_app/features/settings/presentation/settings_providers.dart';
import 'package:parent_app/features/settings/presentation/settings_screen.dart';
import 'package:parent_app/features/settings/presentation/widgets/notification_settings_panel.dart';

/// R48 설정 탭(시안 `settings` · `settings-student`) — 계정 카드 · 자녀 목록의 학년 · 학생 알림 스위치
/// 2개 · 로그아웃 맨 아래.
class _FakeDeviceStorage extends DeviceRegistrationStorage {
  @override
  Future<String> readOrCreateDeviceId() async => 'device-1';

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> clearToken() async {}
}

Future<void> _pump(
  WidgetTester tester, {
  required UserRole role,
  List<Student> students = const [],
}) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        currentUserRoleProvider.overrideWith((ref) => role),
        myProfileProvider.overrideWith(
          (ref) async => MeResponse(
            accountId: 'a-1',
            loginId: 'parentA14',
            name: '이수정',
            phone: '010',
            role: role == UserRole.parent
                ? AccountRole.parent
                : AccountRole.student,
            status: AccountStatus.active,
            academy: const AcademyRef(id: 'ac-1', name: '하늘수학학원 부천중동점'),
          ),
        ),
        myStudentsProvider.overrideWith((ref) async => students),
        deviceRegistrationStorageProvider.overrideWithValue(
          _FakeDeviceStorage(),
        ),
        notificationSettingsProvider.overrideWith(
          (ref) async => const NotificationSettings(
            arrive: true,
            boarding: true,
            noShow: true,
          ),
        ),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('맨 위 계정 카드 — 이름 · 역할 칩 · 학원 · 아이디', (tester) async {
    await _pump(tester, role: UserRole.parent);

    expect(find.text('이수정'), findsWidgets);
    expect(find.text('학부모'), findsOneWidget);
    expect(find.text('하늘수학학원 부천중동점 · parentA14'), findsOneWidget);
  });

  testWidgets('학부모는 "내 자녀 N명" 목록에 학년 · 반 · 연결일이 붙고 자녀 추가가 있다', (tester) async {
    await _pump(
      tester,
      role: UserRole.parent,
      students: [
        Student(
          studentId: 's-1',
          name: '이하준',
          linkedAt: DateTime(2026, 9, 28),
          className: '수학 A반',
          grade: '초5',
        ),
        // 서버가 학년을 아직 안 주는 자녀 — 학년 줄만 빠지고 깨지지 않는다.
        Student(
          studentId: 's-2',
          name: '이서연',
          linkedAt: DateTime(2026, 10),
          className: '수학 B반',
        ),
      ],
    );

    expect(find.text('내 자녀 2명'), findsOneWidget);
    expect(find.text('초5 · 수학 A반 · 9월 28일 연결'), findsOneWidget);
    expect(find.text('수학 B반 · 10월 1일 연결'), findsOneWidget);
    expect(find.text('자녀 추가'), findsOneWidget);
    expect(find.text('연결됨'), findsNWidgets(2));
  });

  testWidgets('학생은 부모님과 연결하기가 있고 자녀 목록은 없다 — 알림 스위치는 2개', (tester) async {
    await _pump(tester, role: UserRole.student);

    expect(find.text('학생'), findsOneWidget);
    expect(find.text('부모님과 연결하기'), findsOneWidget);
    expect(find.textContaining('내 자녀'), findsNothing);
    // 기기 알림 스위치(이 기기)와 따로, 알림 설정 패널 안의 스위치만 센다.
    expect(
      find.descendant(
        of: find.byType(NotificationSettingsPanel),
        matching: find.byType(BaraedaSwitch),
      ),
      findsNWidgets(2),
    );
    expect(find.text('운행 시작 알림'), findsOneWidget);
    expect(find.text('미승차 알림'), findsNothing);
  });

  testWidgets('로그아웃이 맨 아래에 있다 — 보안(비밀번호 변경)보다 아래(Ruling 826)', (tester) async {
    await _pump(tester, role: UserRole.parent);

    final logout = tester.getTopLeft(
      find.widgetWithText(BaraedaButton, '로그아웃'),
    );
    final password = tester.getTopLeft(find.text('비밀번호 변경'));
    expect(logout.dy, greaterThan(password.dy));
    expect(find.text('바꾸면 모든 기기에서 로그아웃돼요'), findsOneWidget);
  });
}
