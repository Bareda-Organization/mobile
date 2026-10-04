import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/routes/domain/route_detail.dart';
import 'package:parent_app/core/routes/presentation/route_providers.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/core/students/presentation/student_switcher.dart';
import 'package:parent_app/core/ui/failure_message.dart';
import 'package:url_launcher/url_launcher.dart';

/// 노선 상세 화면 — P-08 (IMPLEMENTATION_PLAN.md §3.1, §3.10).
///
/// 역할 분기는 `live_map_screen.dart` 와 같은 규칙 하나로만 한다
/// (`roleCapabilitiesProvider.canToggleAttendance`, §1.1) — 학부모는
/// 연결된 자녀 중 선택한 한 명, 학생은 본인 `student_id` 하나.
class RouteDetailScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(roleCapabilitiesProvider);
    final isParent = capabilities?.canToggleAttendance ?? false;

    return Scaffold(
      appBar: const AppHeader(title: '노선 자세히'),
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
  const new();

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

        final selectedId = watchSelectedStudentId(ref, students);

        return Padding(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StudentSwitcher(students: students, selectedId: selectedId),
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
  const new();

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
  const new({required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeAsync = ref.watch(routeDetailProvider(studentId));

    return routeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => AlertBanner(
        tone: AlertTone.missed,
        body: isWithdrawnStudent(error)
            ? withdrawnStudentMessage
            : '노선 정보를 불러오지 못했습니다',
      ),
      data: (route) => _RouteDetailView(
        route: route,
        onRefresh: () async {
          ref.invalidate(routeDetailProvider(studentId));
          await ref
              .read(routeDetailProvider(studentId).future)
              .then<void>((_) {}, onError: (_) {});
        },
      ),
    );
  }
}

class _RouteDetailView extends StatelessWidget {
  const new({required this.route, required this.onRefresh});

  final RouteDetail route;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final departTimeText = DateFormat(
      'HH:mm',
    ).format(route.departTime.toLocal());
    final hasSkipped = route.stops.any(
      (s) => s.change == RouteStopChange.skipped,
    );

    // F05-06 — 당겨서 새로고침. 내용이 짧아도 당겨지도록 항상 스크롤 가능하게 둔다.
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(route.busNo, style: BaraedaTypography.h3),
                    Text(
                      '$departTimeText 출발',
                      style: BaraedaTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 배차가 아직 안 됐어도(P-08) 에러가 아니라 이 칩만 얹고 고정 노선을 그대로 보여준다(위 클래스 문서
              // 참고).
              if (!route.confirmed)
                const BaraedaStatusPill(
                  status: BaraedaStatus.waiting,
                  label: '확정 전',
                ),
            ],
          ),
          const SizedBox(height: BaraedaSpacing.space4),
          if (!route.confirmed) ...[
            const AlertBanner(
              tone: AlertTone.info,
              title: '아직 확정 전이에요',
              body: '지금은 기본 노선이에요. 새로 생긴 곳은 초록색이에요.',
            ),
            const SizedBox(height: BaraedaSpacing.space4),
          ],
          const Text('내 승하차지 앞 2곳과 도착지', style: BaraedaTypography.h3),
          const SizedBox(height: BaraedaSpacing.space2),
          // 서버가 이미 §3.10 범위로 좁혀 보낸 stops 를 그대로 그린다(route_detail.dart 의
          // `RouteDetail.stops` 문서 참고).
          // 지난 곳은 `arrived_at` 으로 "12:09 지남" 을 단다 — 지난 사실이라 ETA 비노출(C-08)과
          // 무관하다.
          StopTimeline(
            stops: [
              for (final stop in route.stops)
                _timelineStop(stop, isMyStop: stop.stopId == route.myStopId),
            ],
          ),
          if (hasSkipped) ...[
            const SizedBox(height: BaraedaSpacing.space2),
            Text(
              '빨간 취소선은 이번 운행에서 서지 않는 곳이에요.',
              style: BaraedaTypography.bodySm.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: BaraedaSpacing.sectionGap),
          const Text('이 버스에 타는 분', style: BaraedaTypography.h3),
          const SizedBox(height: BaraedaSpacing.space2),
          _DriverEscortSection(driver: route.driver, escort: route.escort),
        ],
      ),
    );
  }
}

/// 승하차지 한 곳 → 타임라인 한 줄. 지난 곳은 `12:09 지남`, 정차 안 함은 취소선 + `제외`, 추가는 `추가`.
Stop _timelineStop(RouteStop stop, {required bool isMyStop}) {
  final arrived = stop.arrivedAt;
  final state = switch (stop.change) {
    RouteStopChange.skipped => StopState.skipped,
    RouteStopChange.added => StopState.added,
    null => arrived != null ? StopState.done : StopState.upcoming,
  };
  final (String? tag, BaraedaBadgeTone tone) = switch (stop.change) {
    RouteStopChange.skipped => ('제외', BaraedaBadgeTone.removed),
    RouteStopChange.added => ('추가', BaraedaBadgeTone.added),
    null when isMyStop => ('내 승하차지', BaraedaBadgeTone.brand),
    null => (null, BaraedaBadgeTone.neutral),
  };
  return Stop(
    name: stop.name,
    address: stop.address,
    time: arrived == null ? null : '${formatClock(arrived)} 지남',
    state: state,
    tag: tag,
    tagTone: tone,
  );
}

/// 기사·동승자 — 연락 버튼은 동승자만 갖는다. 기사는 연락처 필드 자체가 서버 응답에 없다
/// (`RouteDriver` 에 `phone` 이 부재 — API_SPEC §3.10). 운전 중이라 연락은 동승자에게 한다.
class _DriverEscortSection extends StatelessWidget {
  const new({required this.driver, required this.escort});

  final RouteDriver driver;
  final RouteEscort escort;

  @override
  Widget build(BuildContext context) {
    return BaraedaListGroup(
      children: [
        BaraedaListRow(
          leadingIcon: 'bus',
          title: '기사 ${driver.name ?? '미배치'}',
          titleIsPersonName: true,
          subtitle: '운전 중이라 연락은 동승자에게',
        ),
        BaraedaListRow(
          leadingIcon: 'user-round',
          title: '동승자 ${escort.name ?? '미배치'}',
          titleIsPersonName: true,
          subtitle: '궁금한 건 동승자에게 전화해요',
          trailing: escort.phone == null
              ? null
              : BaraedaButton(
                  label: '전화',
                  size: BaraedaButtonSize.sm,
                  variant: BaraedaButtonVariant.secondary,
                  icon: 'phone',
                  name: '동승자에게',
                  onPressed: () => _callEscort(escort.phone!),
                ),
        ),
      ],
    );
  }

  Future<void> _callEscort(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri);
  }
}
