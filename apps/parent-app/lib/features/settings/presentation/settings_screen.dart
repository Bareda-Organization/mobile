import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/core/auth/account_session.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/devices/presentation/device_registration_panel.dart';
import 'package:parent_app/core/students/domain/student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/features/settings/presentation/settings_providers.dart';
import 'package:parent_app/features/settings/presentation/widgets/notification_settings_panel.dart';

/// 설정 탭 — P-09 · S-03 (R48 시안 `settings` · `settings-student`).
///
/// 맨 위가 계정 카드(이름 · 역할 · 학원 · 아이디), 학부모는 `내 자녀 N명` 과 `자녀 추가`, 학생은 `부모님과 연결하기` 가
/// 이어진다. **로그아웃은 맨 아래, 이 탭에만 있다**(`Ruling 826` — 홈 머리말에서 뺐다). 되돌릴 수 없는 동작이라
/// 확인 대화 1회를 거친다.
class SettingsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isParent =
        ref.watch(roleCapabilitiesProvider)?.canToggleAttendance ?? false;

    return Scaffold(
      appBar: const AppHeader(title: '설정'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          children: [
            _AccountCard(isParent: isParent),
            const SizedBox(height: BaraedaSpacing.sectionGap),
            if (isParent)
              const _ChildrenSection()
            else
              const _ParentLinkSection(),
            const SizedBox(height: BaraedaSpacing.sectionGap),
            const _SectionTitle('알림'),
            NotificationSettingsPanel(isParent: isParent),
            const SizedBox(height: BaraedaSpacing.sectionGap),
            const _SectionTitle('이 기기'),
            const DeviceRegistrationPanel(),
            const SizedBox(height: BaraedaSpacing.sectionGap),
            const _SectionTitle('보안'),
            BaraedaListGroup(
              children: [
                BaraedaListRow(
                  leadingIcon: 'lock',
                  title: '비밀번호 변경',
                  subtitle: '바꾸면 모든 기기에서 로그아웃돼요',
                  trailing: const BaraedaIcon('chevron-right'),
                  onTap: () => context.push(AppRoutes.passwordChange),
                ),
              ],
            ),
            const SizedBox(height: BaraedaSpacing.sectionGap),
            // 로그아웃 — 역할이 비면 라우터가 로그인 화면으로 보낸다. 같은 확인 대화를
            // `pending_approval_screen.dart` 도
            // 재사용한다(`core/auth/account_session.dart` 의 [confirmLogout]).
            BaraedaButton(
              label: '로그아웃',
              icon: 'log-out',
              variant: BaraedaButtonVariant.secondary,
              block: true,
              onPressed: () => confirmLogout(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BaraedaSpacing.space2),
      child: Semantics(
        header: true,
        child: Text(text, style: BaraedaTypography.h3),
      ),
    );
  }
}

/// 계정 카드 — 이름 · 역할 칩 · `학원 · 아이디`. 내 정보를 못 받으면 카드를 그리지 않는다(나머지 설정은 그대로 쓴다).
class _AccountCard extends ConsumerWidget {
  const new({required this.isParent});

  final bool isParent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfileProvider).value;
    if (me == null) return const SizedBox.shrink();
    final colors = context.colors;
    final subtitle = [?me.academy?.name, me.loginId].join(' · ');

    return BaraedaCard(
      child: Row(
        children: [
          _Avatar(name: me.name, size: 44),
          const SizedBox(width: BaraedaSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        me.name,
                        maxLines: 2,
                        style: BaraedaTypography.bodyLg.copyWith(
                          fontWeight: BaraedaFontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: BaraedaSpacing.space2),
                    BaraedaBadge(
                      label: isParent ? '학부모' : '학생',
                      tone: BaraedaBadgeTone.brand,
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BaraedaTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const new({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.accentPrimarySoft,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Text(
              name.isEmpty ? '' : name.characters.first,
              style: BaraedaTypography.body.copyWith(
                color: colors.textPrimary,
                fontWeight: BaraedaFontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 학부모 — `내 자녀 N명` 목록(학년 · 반 · 연결일 · 연결됨 칩)과 `자녀 추가`.
class _ChildrenSection extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final students = ref.watch(myStudentsProvider).value ?? const <Student>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle('내 자녀 ${students.length}명'),
        BaraedaListGroup(
          children: [
            for (final student in students)
              BaraedaListRow(
                leading: _Avatar(name: student.name, size: 40),
                title: student.name,
                titleIsPersonName: true,
                subtitle: childSubtitle(student),
                trailing: const BaraedaStatusPill(
                  status: BaraedaStatus.boarded,
                  label: '연결됨',
                ),
              ),
            BaraedaListRow(
              leadingIcon: 'user-plus',
              title: '자녀 추가',
              subtitle: '자녀 앱에서 만든 연결 코드를 입력해요',
              trailing: const BaraedaIcon('chevron-right'),
              onTap: () => context.push(AppRoutes.childLink),
            ),
          ],
        ),
      ],
    );
  }
}

/// `초5 · 수학 A반 · 9월 28일 연결` — 학년·반은 서버가 줄 때만 붙는다(`Ruling 824`).
String childSubtitle(Student student) {
  final linked = student.linkedAt.toLocal();
  return [
    ?student.grade,
    ?student.className,
    '${linked.month}월 ${linked.day}일 연결',
  ].join(' · ');
}

/// 학생 — 부모님과 연결하기(연결 코드 만들기, S-05).
class _ParentLinkSection extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('부모님'),
        BaraedaListGroup(
          children: [
            BaraedaListRow(
              leadingIcon: 'link',
              title: '부모님과 연결하기',
              subtitle: '연결 코드를 만들어 부모님께 알려 주세요',
              trailing: const BaraedaIcon('chevron-right'),
              onTap: () => context.push(AppRoutes.childLink),
            ),
          ],
        ),
      ],
    );
  }
}
