import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/route/domain/route_detail.dart';
import 'package:parent_app/features/route/presentation/route_providers.dart';
import 'package:url_launcher/url_launcher.dart';

/// 노선 상세 화면 — P-08 (IMPLEMENTATION_PLAN.md §3.1, §3.10).
///
/// 역할 분기는 `live_map_screen.dart` 와 같은 규칙 하나로만 한다
/// (`roleCapabilitiesProvider.canToggleAttendance`, §1.1) — 학부모는
/// 연결된 자녀 중 선택한 한 명, 학생은 본인 `student_id` 하나.
class RouteDetailScreen extends ConsumerWidget {
  const RouteDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(roleCapabilitiesProvider);
    final isParent = capabilities?.canToggleAttendance ?? false;

    return Scaffold(
      appBar: const AppHeader(title: '노선 상세'),
      body: SafeArea(
        child: isParent
            ? const _ParentRouteDetail()
            : const _StudentRouteDetail(),
      ),
    );
  }
}

/// 학부모 갈래 — `live_map_screen.dart` `_ParentLiveMap` 과 같은
/// `selectedStudentIdProvider` 를 공유해, 홈·자리표시에서 고른 자녀가
/// 이 화면에도 그대로 이어진다.
class _ParentRouteDetail extends ConsumerWidget {
  const _ParentRouteDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(myStudentsProvider);

    return studentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          const AlertBanner(tone: AlertTone.missed, body: '자녀 목록을 불러오지 못했습니다'),
      data: (students) {
        if (students.isEmpty) {
          return EmptyState(
            title: '연결된 자녀가 없습니다',
            body: '자녀 연결을 먼저 진행해 주세요',
            action: BaraedaButton(
              label: '자녀 연결하기',
              onPressed: () => context.push(AppRoutes.childLink),
            ),
          );
        }

        final selectedId =
            ref.watch(selectedStudentIdProvider) ?? students.first.studentId;

        return Padding(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (students.length > 1) ...[
                BaraedaSelect(
                  label: '자녀 선택',
                  value: selectedId,
                  options: students
                      .map(
                        (s) => BaraedaSelectOption(s.studentId, label: s.name),
                      )
                      .toList(),
                  onChanged: (value) =>
                      ref.read(selectedStudentIdProvider.notifier).state =
                          value,
                ),
                const SizedBox(height: BaraedaSpacing.space4),
              ],
              Expanded(child: _RouteDetailBody(studentId: selectedId)),
            ],
          ),
        );
      },
    );
  }
}

/// 학생 갈래 — 본인 `student_id` 하나만 쓴다(조회 전용).
class _StudentRouteDetail extends ConsumerWidget {
  const _StudentRouteDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentIdAsync = ref.watch(myStudentIdProvider);

    return studentIdAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          const AlertBanner(tone: AlertTone.missed, body: '내 정보를 불러오지 못했습니다'),
      data: (studentId) => studentId == null
          ? const EmptyState(title: '학생 계정 정보가 없습니다')
          : Padding(
              padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
              child: _RouteDetailBody(studentId: studentId),
            ),
    );
  }
}

/// `routeDetailProvider(studentId)` 를 그려주는 본체.
///
/// **판단 근거 — "확정 전" 은 에러가 아니라 데이터다** (API_SPEC §3.10
/// 에러 표 마지막 줄 — "확정 전은 에러 부재, 고정 노선 + 배지로 반환").
/// `confirmed == false` 여도 서버가 고정(기본) 노선을 그대로 돌려주므로,
/// 이 위젯은 `error` 분기가 아니라 `data` 분기 안에서 배지만 얹는다 —
/// 별도의 "미확정" 에러 화면을 만들지 않는다. `404`·`403` 등 실제 에러는
/// `error` 분기가 받아 고정 문구로 안내한다(다른 화면과 같은 관례,
/// `schedule_screen.dart` 등).
class _RouteDetailBody extends ConsumerWidget {
  const _RouteDetailBody({required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeAsync = ref.watch(routeDetailProvider(studentId));

    return routeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          const AlertBanner(tone: AlertTone.missed, body: '노선 정보를 불러오지 못했습니다'),
      data: (route) => _RouteDetailView(route: route),
    );
  }
}

class _RouteDetailView extends StatelessWidget {
  const _RouteDetailView({required this.route});

  final RouteDetail route;

  @override
  Widget build(BuildContext context) {
    final departTimeText = DateFormat('HH:mm').format(route.departTime);

    return ListView(
      children: [
        BaraedaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${route.busNo}호차 · $departTimeText 출발',
                      style: BaraedaTypography.h3,
                    ),
                  ),
                  // 배차가 아직 안 됐어도(P-08) 에러가 아니라 이 배지만
                  // 얹고 고정 노선을 그대로 보여준다(위 클래스 문서 참고).
                  if (!route.confirmed)
                    const BaraedaBadge(
                      label: '확정 전',
                      tone: BaraedaBadgeTone.amber,
                    ),
                ],
              ),
              const SizedBox(height: BaraedaSpacing.space4),
              _DriverEscortSection(driver: route.driver, escort: route.escort),
            ],
          ),
        ),
        const SizedBox(height: BaraedaSpacing.sectionGap),
        const Text('경유 승하차지', style: BaraedaTypography.h3),
        const SizedBox(height: BaraedaSpacing.space2),
        // 서버가 이미 "승차지 이전 2개 · 승차지 · 하차지" 로 창을 좁혀
        // 보낸다(P-08) — 이 목록을 다시 자르지 않는다(route_detail.dart
        // 클래스 문서와 같은 판단).
        ...route.stops.map(
          (stop) => _RouteStopTile(
            stop: stop,
            isMyStop: stop.stopId == route.myStopId,
          ),
        ),
      ],
    );
  }
}

/// 기사·동승자 — 연락 버튼은 동승자만 갖는다. 기사는 연락처 필드 자체가
/// 서버 응답에 없다(`RouteDriver` 에 `phone` 이 부재 — API_SPEC §3.10).
class _DriverEscortSection extends StatelessWidget {
  const _DriverEscortSection({required this.driver, required this.escort});

  final RouteDriver driver;
  final RouteEscort escort;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('기사 ${driver.name}', style: BaraedaTypography.body),
        const SizedBox(height: BaraedaSpacing.space2),
        Row(
          children: [
            Expanded(
              child: Text('동승자 ${escort.name}', style: BaraedaTypography.body),
            ),
            BaraedaButton(
              label: '전화하기',
              size: BaraedaButtonSize.sm,
              variant: BaraedaButtonVariant.secondary,
              icon: 'phone',
              onPressed: () => _callEscort(escort.phone),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _callEscort(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri);
  }
}

class _RouteStopTile extends StatelessWidget {
  const _RouteStopTile({required this.stop, required this.isMyStop});

  final RouteStop stop;
  final bool isMyStop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BaraedaSpacing.space2),
      child: BaraedaCard(
        tone: isMyStop ? BaraedaCardTone.mist : BaraedaCardTone.base,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(stop.name, style: BaraedaTypography.body),
                      if (isMyStop) ...[
                        const SizedBox(width: BaraedaSpacing.space2),
                        const BaraedaBadge(
                          label: '내 승하차지',
                          tone: BaraedaBadgeTone.brand,
                        ),
                      ],
                      if (stop.change != null) ...[
                        const SizedBox(width: BaraedaSpacing.space2),
                        BaraedaBadge(
                          label: stop.change == RouteStopChange.added
                              ? '추가'
                              : '제외',
                          tone: stop.change == RouteStopChange.added
                              ? BaraedaBadgeTone.added
                              : BaraedaBadgeTone.removed,
                        ),
                      ],
                    ],
                  ),
                  Text(stop.address, style: BaraedaTypography.bodySm),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
