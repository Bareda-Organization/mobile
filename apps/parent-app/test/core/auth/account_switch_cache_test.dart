import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/auth/user_role.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/domain/student_repository.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/notifications/domain/notification_item.dart';
import 'package:parent_app/features/notifications/domain/notification_repository.dart';
import 'package:parent_app/features/notifications/presentation/notification_providers.dart';

class _CountingStudents implements StudentRepository {
  int calls = 0;

  @override
  Future<List<Student>> getMyStudents() async {
    calls++;
    return [
      Student(
        studentId: 's-$calls',
        name: '자녀$calls',
        linkedAt: DateTime(2026),
      ),
    ];
  }
}

class _CountingNotifications implements NotificationRepository {
  int calls = 0;

  @override
  Future<NotificationPage> getNotifications({
    int page = 0,
    int size = 20,
    bool unreadOnly = false,
  }) async {
    calls++;
    return NotificationPage(
      items: const [],
      page: page,
      size: size,
      totalCount: 0,
      hasNext: false,
      unreadCount: 0,
    );
  }

  @override
  Future<void> markRead(String notificationId) async {}
}

/// F05-01 — 한 기기를 두 계정이 나눠 쓴다(UF-X-03 "로그아웃 후 다른 계정"). 로그아웃(역할 null)을
/// 지나면 앞 계정이 받아 둔 자녀·알림·고른 자녀가 다음 계정에 보이면 안 된다.
void main() {
  test('로그아웃을 지나 다시 로그인하면 자녀·알림·고른 자녀를 새로 받는다', () async {
    final students = _CountingStudents();
    final notifications = _CountingNotifications();
    final container = ProviderContainer(
      overrides: [
        studentRepositoryProvider.overrideWithValue(students),
        notificationRepositoryProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentUserRoleProvider.notifier).state =
        UserRole.values.first;
    await container.read(myStudentsProvider.future);
    await container.read(notificationFeedProvider.future);
    container.read(selectedStudentIdProvider.notifier).state = 's-A';

    // 로그아웃 → 다른 계정 로그인
    container.read(currentUserRoleProvider.notifier).state = null;
    container.read(currentUserRoleProvider.notifier).state =
        UserRole.values.first;

    final second = await container.read(myStudentsProvider.future);
    await container.read(notificationFeedProvider.future);

    expect(students.calls, 2, reason: '자녀 목록은 계정마다 새로 받아야 한다');
    expect(second.single.name, '자녀2');
    expect(notifications.calls, 2);
    expect(container.read(selectedStudentIdProvider), isNull);
  });
}
