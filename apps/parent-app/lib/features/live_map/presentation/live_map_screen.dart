import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/map/map_surface.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/features/home/presentation/home_providers.dart';
import 'package:parent_app/features/live_map/domain/bus_position.dart';
import 'package:parent_app/features/live_map/domain/live_map_status.dart';
import 'package:parent_app/features/live_map/presentation/live_map_providers.dart';

/// Ruling 208 — 마지막 수신 후 2분이면 유실로 판정한다. 서버
/// (`API_SPEC §3.11`)의 `StudentBusPositionQueryService.STALE_THRESHOLD`
/// 와 같은 값이어야 한다 — 갈라 두면 REST 스냅샷은 정상인데 WS 화면은
/// 유실로 보이는(또는 그 반대) 구간이 생긴다.
const _positionStaleThreshold = Duration(minutes: 2);

/// 자리표시 화면 — P-07 (IMPLEMENTATION_PLAN.md §3.1, §3.11 · §7 WebSocket).
/// 실시간 버스 위치 지도는 F4-B 1단계에서 붙었다 — `/topic/students/{studentId}/run`
/// 4종 이벤트를 화면 상태로 반영하는 것은 그대로이고, `position` 이벤트가
/// 있을 때만 [MapSurface] 로 버스 위치를 그린다(이 파일 아래 `_LiveMapBody`
/// 문서 참고). 화면은 `core/map/map_surface.dart` 계약만 보고 SDK 타입은
/// 절대 직접 참조하지 않는다 — 근거는 `core/map/map_surface.dart` 문서.
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
      appBar: const AppHeader(title: '실시간 버스 위치'),
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
              const SizedBox(height: BaraedaSpacing.space4),
              // UF-P-07 — 지도 다음 단계가 "[노선 자세히 보기]" 다. 이 버튼이 없어서
              // RouteDetailScreen 에 도달할 길이 부재했다(2026-09-21).
              BaraedaButton(
                label: '노선 자세히 보기',
                variant: BaraedaButtonVariant.ghost,
                onPressed: () => context.push(AppRoutes.routeDetail),
              ),
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
///
/// **판단 근거 — 지도는 `state.position` 이 있을 때만 그린다.**
/// `docs/USER_FLOWS.md` UF-P-07 은 "(운행 시간 아님) → 지도 대신 '운행
/// 예정 시간' 안내"라고 명시한다 — 즉 좌표가 없는 상태에서 지도를 먼저
/// 보여주면 안 되고, 그 상태의 문구는 이미 위 `EmptyState` 분기가 사양대로
/// 채우고 있다. 지도는 그 문구를 대체하지 않고 데이터가 실제로 있는
/// 목록 맨 위에 얹는다. `run_started` 만 와서 `hasNoData` 는 거짓인데
/// `position` 은 아직 없는 좁은 경우(사양이 다루지 않는 틈)에는 지도
/// 대신 "위치 신호 대기 중" 문구를 짧게 둔다 — 근거 없는 임의의 카메라
/// 위치(예: 학원 좌표)를 기본값으로 잡지 않기 위해서다(보고서 §1 참고).
///
/// **P1(Ruling 208·349) — WS 로 받은 좌표도 2분이 지나면 유실로 본다.**
/// 아래 `staleSinceText` 는 서버가 §3.11 REST 응답에서 이미 유실로
/// 판정해 좌표를 안 준 경우다. 반대로 WS 로 한 번 받은 좌표(`state.position`)
/// 는 연결 자체가 끊기지 않아도 방송만 멈추면(Ruling 349 — 과부하 때
/// `position` 방송은 버려질 수 있다) 서버가 다시 판정해 줄 기회가 없다
/// — 그래서 이 화면이 매 빌드마다 `clockProvider` 로 직접 잰다.
class _LiveMapBody extends ConsumerWidget {
  const _LiveMapBody({required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveMapStateProvider(studentId));
    final connection = state.connection;

    // 당일 결석(§3.11) — WS 연결 상태와 무관하게 가장 먼저 가른다. 결석은
    // 그날 하루의 확정된 사실이라, 마침 연결이 살아있어도 뒤집히지 않는다.
    if (state.isAbsent) {
      return const EmptyState(title: '오늘은 버스를 이용하지 않습니다');
    }

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

    // §3.11 REST 스냅샷 — WS 구독과 별개로 첫 진입 시 한 번 받은 결과.
    // WS 가 아직 아무 좌표도 주지 않은 동안의 대체 표시로만 쓰고,
    // `state.position`(WS)이 오면 그쪽을 항상 우선한다.
    final restPositionAsync = state.restPosition;
    final restPosition = restPositionAsync is AsyncData<BusPosition>
        ? restPositionAsync.value
        : null;

    final now = ref.watch(clockProvider).now();

    // 신호 유실(Ruling 208 — 마지막 수신 후 2분) — 서버가 좌표 없이
    // `last_seen_at` 만 돌려준 경우다. `run_status` 가 `moving` 이 아니면서
    // `last_seen_at` 도 없는 것은 유실이 아니라 그냥 운행 전·후 상태이므로
    // (판단 근거 — 완료 조건) 여기서 배너를 띄우지 않고 기존 "위치 신호
    // 대기 중"·"아직 위치 정보가 없습니다" 문구로 자연히 떨어진다.
    final staleMinutesAgo =
        state.position == null &&
            restPosition != null &&
            restPosition.lat == null &&
            restPosition.lastSeenAt != null
        ? now.difference(restPosition.lastSeenAt!).inMinutes
        : null;
    final staleSinceText = staleMinutesAgo == null
        ? null
        : '마지막 확인 위치 · $staleMinutesAgo분 전';

    // WS 가 아직 못 받은 좌표를 REST 스냅샷으로 메운다 — `receivedAt` 이
    // 없으면(서버가 시각을 안 줌) 합성하지 않는다. `eta` 는 채우지 않는다
    // (§7.1 — 학부모·학생 채널은 ETA 를 절대 받지 않는다, C-08).
    final restSyntheticPosition =
        state.position == null &&
            restPosition != null &&
            restPosition.lat != null &&
            restPosition.lng != null &&
            restPosition.receivedAt != null
        ? WsPositionPayload(
            lat: restPosition.lat!,
            lng: restPosition.lng!,
            receivedAt: restPosition.receivedAt!,
            currentStopName: restPosition.currentStopName,
          )
        : null;

    // P1 — 지금 화면이 표시할 좌표(WS 우선, 없으면 위 REST 대체)가 그 자체로
    // 2분을 넘겼는지 클래스 문서에서 밝힌 이유로 다시 잰다. `staleSinceText`
    // 와 동시에 값이 있을 일은 없다 — 저쪽이 서면 이쪽의 두 후보(`state.position`·
    // `restSyntheticPosition`)가 이미 둘 다 null 이기 때문이다.
    final effectivePosition = state.position ?? restSyntheticPosition;
    final effectiveStaleMinutesAgo =
        effectivePosition != null &&
            now.difference(effectivePosition.receivedAt) >=
                _positionStaleThreshold
        ? now.difference(effectivePosition.receivedAt).inMinutes
        : null;
    final effectiveStaleSinceText = effectiveStaleMinutesAgo == null
        ? null
        : '마지막 확인 위치 · $effectiveStaleMinutesAgo분 전';
    final resolvedStaleText = staleSinceText ?? effectiveStaleSinceText;
    final hasFreshPosition =
        effectivePosition != null && effectiveStaleSinceText == null;

    if (resolvedStaleText != null && state.hasNoData) {
      return EmptyState(
        title: resolvedStaleText,
        body: '신호가 다시 잡히면 자동으로 갱신됩니다',
      );
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
        if (hasFreshPosition)
          _BusMapSection(studentId: studentId, position: effectivePosition)
        else if (resolvedStaleText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: BaraedaSpacing.space4),
            child: Text(resolvedStaleText, style: BaraedaTypography.bodySm),
          )
        else if (!state.hasNoData)
          // 좌표는 아직 없지만(`run_started` 만 온 상태 등) "데이터 없음"도
          // 아닌 좁은 경우 — 지도 자리 대신 짧은 안내만 둔다(위 클래스
          // 문서 판단 근거 참고).
          const Padding(
            padding: EdgeInsets.only(bottom: BaraedaSpacing.space4),
            child: Text('위치 신호 대기 중', style: BaraedaTypography.bodySm),
          ),
        if (state.runStarted != null)
          _EventTile(
            label: '운행 시작',
            time: state.runStarted!.startedAt,
          ),
        if (hasFreshPosition) _PositionTile(position: effectivePosition),
        if (state.lastStopArrived != null)
          _EventTile(
            label: '${state.lastStopArrived!.name} 도착',
            time: state.lastStopArrived!.arrivedAt,
          ),
        if (state.runEnded != null)
          _EventTile(
            label: '운행 종료',
            time: state.runEnded!.finishedAt,
          ),
      ],
    );
  }
}

/// 버스 마커 지도 한 칸 — 목표 7(F4-B 2단계): SDK 인증 실패를 화면에
/// 직접 보여준다.
///
/// **판단 근거 — `debugPrint` 만으로 두지 않는 이유** (1단계 이월):
/// `debugPrint` 는 개발자만 본다. 사용자가 왜 지도가 안 뜨는지 알 방법이
/// 없어 "빈 화면" 결함처럼 보인다.
///
/// **판단 근거 — 원인(도메인 불일치 vs 키 만료)을 가르지 않고 뭉뚱그린
/// 문구 하나로 두는 이유**: `NaverMapInit.onAuthFailed` 가 넘기는
/// 예외는 SDK 가 던지는 원본 그대로이고(팀 공통 규칙 — 오류 분류는
/// 호출부 몫), 실제로 원인별로 다른 문구를 보여줄 만큼 안정적으로
/// 가를 수 있는 필드가 없다(§8.3 실측). 가를 수 없는 것을 가르는 척
/// 하면 오히려 오진을 보여주게 되므로, 이 화면은 "지도를 불러오지
/// 못했습니다" 한 줄만 보여주고 원인 구분은 로그(`debugPrint`)에만
/// 남긴다.
///
/// **판단 근거 — 상태를 `LiveMapNotifier`/`LiveMapState` 에 넣지 않고
/// 이 위젯 로컬 상태로 둔 이유**: 지도 SDK 인증 실패는 WebSocket 연결
/// 상태와 원인이 다른 별개 채널이다. 그 둘을 한 상태 클래스에 합치면
/// "연결 끊김"과 "지도 인증 실패"가 같은 `copyWith` 경합에 얽혀 순서
/// 버그를 만들기 쉽다 — 화면에 한 번 그려지고 나면 다시 사라질 일이
/// 없는 상태라 `StatefulWidget` 로 충분하다.
class _BusMapSection extends StatefulWidget {
  const _BusMapSection({required this.studentId, required this.position});

  final String studentId;
  final WsPositionPayload position;

  @override
  State<_BusMapSection> createState() => _BusMapSectionState();
}

class _BusMapSectionState extends State<_BusMapSection> {
  bool _authFailed = false;

  @override
  Widget build(BuildContext context) {
    if (_authFailed) {
      return const Padding(
        padding: EdgeInsets.only(bottom: BaraedaSpacing.space4),
        child: AlertBanner(tone: AlertTone.missed, body: '지도를 불러오지 못했습니다'),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: BaraedaSpacing.space4),
      child: SizedBox(
        height: 240,
        child: MapSurface(
          camera: MapCamera(lat: widget.position.lat, lng: widget.position.lng),
          markers: [
            MapMarker(
              id: 'bus-${widget.studentId}',
              lat: widget.position.lat,
              lng: widget.position.lng,
              kind: MapMarkerKind.bus,
            ),
          ],
          onAuthFailed: (exception) {
            debugPrint('네이버 지도 인증 실패: $exception');
            if (mounted) setState(() => _authFailed = true);
          },
        ),
      ),
    );
  }
}

/// **판단 근거 — ETA 를 그리지 않는 이유.** `WsPositionPayload.eta` 필드가
/// 남아 있어도 이 타일은 절대 표시하지 않는다 — API_SPEC §7.1 "학부모·
/// 학생 채널은 ETA 를 절대 받지 않는다"(C-08)와 §3.10 "승하차지별 탑승
/// 인원 · ETA 부재"가 명시적으로 금지한다. 예전 구현이 `position.eta`
/// 를 조건부로 그리고 있었던 것은 이 화면이 참조하는 채널이 원래 ETA
/// 를 보내지 않아 드러나지 않았을 뿐인 사양 위반이라 이번에 제거한다.
class _PositionTile extends StatelessWidget {
  const _PositionTile({required this.position});

  final WsPositionPayload position;

  @override
  Widget build(BuildContext context) {
    final timeText = DateFormat(
      'HH:mm:ss',
    ).format(position.receivedAt.toLocal());
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
        ],
      ),
    );
  }
}

/// 운행 이벤트 한 줄. 운행 시작·종료에 인원수를 붙이지 않는다 — 학부모·학생 앱은 탑승 인원을
/// 표시하지 않고(C-08) 학생 채널에도 실리지 않는다(Ruling 335).
class _EventTile extends StatelessWidget {
  const _EventTile({required this.label, required this.time});

  final String label;
  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final timeText = DateFormat('HH:mm:ss').format(time.toLocal());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BaraedaSpacing.space2),
      child: Text('$label · $timeText', style: BaraedaTypography.body),
    );
  }
}
