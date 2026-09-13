import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/live_map/domain/live_map_status.dart';
import 'package:parent_app/features/live_map/presentation/live_map_providers.dart';

/// 자리표시 화면 — P-07 (IMPLEMENTATION_PLAN.md §3.1, §3.11 · §7 WebSocket).
/// 실시간 버스 위치 지도는 이번 범위가 아니다(F4-B) — 여기서는
/// `/topic/students/{studentId}/run` 4종 이벤트를 화면 상태로만 반영한다.
///
/// 역할 분기는 `home_screen.dart` 와 같은 규칙 하나로만 한다
/// (`roleCapabilitiesProvider.canToggleAttendance`, §1.1) — 학부모는
/// 연결된 자녀 중 선택한 한 명, 학생은 본인 `student_id` 하나.
class LiveMapScreen extends ConsumerWidget {
  const LiveMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(roleCapabilitiesProvider);
    final isParent = capabilities?.canToggleAttendance ?? false;

    return Scaffold(
      appBar: const AppHeader(title: '자리표시'),
      body: SafeArea(
        child: isParent ? const _ParentLiveMap() : const _StudentLiveMap(),
      ),
    );
  }
}

/// 학부모 갈래 — 자녀가 여럿이면 하나를 골라야 한다(`home_screen.dart`
/// `_ParentSection` 과 같은 `selectedStudentIdProvider` 를 공유해, 홈에서
/// 고른 자녀가 이 화면에도 그대로 이어진다).
class _ParentLiveMap extends ConsumerWidget {
  const _ParentLiveMap();

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
              Expanded(child: _LiveMapBody(studentId: selectedId)),
            ],
          ),
        );
      },
    );
  }
}

/// 학생 갈래 — 본인 `student_id` 하나만 쓴다(조회 전용).
class _StudentLiveMap extends ConsumerWidget {
  const _StudentLiveMap();

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
              child: _LiveMapBody(studentId: studentId),
            ),
    );
  }
}

/// 실제 WebSocket 상태를 그리는 자리 — `studentId` 가 정해진 뒤에만 만든다.
///
/// **완료 조건 9(공유 목표) — "데이터 없음"과 "연결 끊김"을 반드시
/// 구분한다.** `FE-R2 목표1`(관리자 웹 조회 실패 시 `EmptyState` 오표시
/// 방지, `git show 9a468928`)과 같은 자리에 같은 모양의 가드를 둔다 —
/// `connection.isLost` 를 [EmptyState] 분기보다 먼저 검사해, 연결이
/// 끊긴 상태에서 "표시할 데이터가 없다"는 문구가 함께 뜨지 않게 한다.
class _LiveMapBody extends ConsumerWidget {
  const _LiveMapBody({required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveMapStateProvider(studentId));
    final connection = state.connection;

    // 순서가 핵심이다 — 연결 끊김을 먼저 걸러야 "데이터 없음"과 겹치지
    // 않는다(위 클래스 문서 참고).
    if (connection.isLost) {
      return AlertBanner(
        tone: AlertTone.missed,
        title: connection == LiveMapConnection.forbidden ? '조회 권한 없음' : '연결 끊김',
        body: connection == LiveMapConnection.forbidden
            ? '이 회차의 위치 정보를 볼 권한이 없습니다'
            : '실시간 위치 연결이 끊어졌습니다. 다시 시도해 주세요',
      );
    }

    if (connection.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.hasNoData) {
      return const EmptyState(
        title: '아직 위치 정보가 없습니다',
        body: '버스가 운행을 시작하면 실시간 위치가 표시됩니다',
      );
    }

    return ListView(
      children: [
        if (connection == LiveMapConnection.reconnecting)
          const Padding(
            padding: EdgeInsets.only(bottom: BaraedaSpacing.space4),
            child: AlertBanner(tone: AlertTone.missed, body: '재연결 시도 중입니다'),
          ),
        if (state.runStarted != null)
          _EventTile(
            label: '운행 시작',
            time: state.runStarted!.startedAt,
            detail: '자동 탑승 처리 ${state.runStarted!.autoBoardedCount}명',
          ),
        if (state.position != null) _PositionTile(position: state.position!),
        if (state.lastStopArrived != null)
          _EventTile(
            label: '${state.lastStopArrived!.name} 도착',
            time: state.lastStopArrived!.arrivedAt,
          ),
        if (state.runEnded != null)
          _EventTile(
            label: '운행 종료',
            time: state.runEnded!.finishedAt,
            detail: '자동 하차 처리 ${state.runEnded!.autoAlightedCount}명',
          ),
      ],
    );
  }
}

class _PositionTile extends StatelessWidget {
  const _PositionTile({required this.position});

  final WsPositionPayload position;

  @override
  Widget build(BuildContext context) {
    final timeText = DateFormat('HH:mm:ss').format(position.receivedAt);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BaraedaSpacing.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('현재 위치 · $timeText 기준', style: BaraedaTypography.bodySm),
          if (position.currentStopName != null)
            Text(
              '가장 가까운 승하차지: ${position.currentStopName}',
              style: BaraedaTypography.body,
            ),
          if (position.eta != null)
            Text('도착 예정: ${position.eta}', style: BaraedaTypography.body),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.label, required this.time, this.detail});

  final String label;
  final DateTime time;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final timeText = DateFormat('HH:mm:ss').format(time);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BaraedaSpacing.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label · $timeText', style: BaraedaTypography.body),
          if (detail != null)
            Text(detail!, style: BaraedaTypography.bodySm),
        ],
      ),
    );
  }
}
