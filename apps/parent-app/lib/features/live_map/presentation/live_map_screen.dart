import 'dart:async';

import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/map/map_surface.dart';
import 'package:parent_app/core/routes/domain/route_detail.dart';
import 'package:parent_app/core/routes/presentation/route_map_overlay.dart';
import 'package:parent_app/core/routes/presentation/route_providers.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';
import 'package:parent_app/core/students/presentation/selected_student.dart';
import 'package:parent_app/core/students/presentation/student_providers.dart';
import 'package:parent_app/core/students/presentation/student_switcher.dart';
import 'package:parent_app/core/ui/delay_band.dart';
import 'package:parent_app/features/live_map/presentation/live_map_providers.dart';
import 'package:parent_app/features/live_map/presentation/live_map_view.dart';
import 'package:parent_app/features/live_map/presentation/trip_text.dart';
import 'package:parent_app/features/live_map/presentation/widgets/live_map_before.dart';
import 'package:parent_app/features/live_map/presentation/widgets/live_map_sheet.dart';

/// P-07 · S-02 실시간 버스 위치 (UF-P-07, `API_SPEC §3.11 · §7`) — 전체 화면 지도 위에 아래 시트를
/// 얹는 구성(R48 시안 `live-map*`).
///
/// 어떤 모양을 그릴지는 [LiveMapView.resolve] 가 정하고(운행 전 · 달리는 중 · 신호 없음 · 연결 끊김 · 종료 ·
/// 불러오는 중 ·
/// 결석), 이 파일은 그 값을 그리기만 한다. 화면은 `core/map/map_surface.dart` 계약만 보고 SDK 타입은 직접
/// 참조하지 않는다.
///
/// 역할 분기는 `home_screen.dart` 와 같은 규칙 하나로만
/// 한다(`roleCapabilitiesProvider.canToggleAttendance`, §1.1) —
/// 학부모는 연결된 자녀 중 선택한 한 명, 학생은 본인 `student_id` 하나.
class LiveMapScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(roleCapabilitiesProvider);
    final isParent = capabilities?.canToggleAttendance ?? false;

    return isParent ? const _ParentLiveMap() : const _StudentLiveMap();
  }
}

/// 지도 밖 화면 틀 — 아직 누구의 버스인지 정해지지 않았거나 지도를 그릴 일이 없을 때(불러오는 중 · 오류 · 자녀 없음).
class _PlainPage extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: _screenTitle),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(BaraedaSpacing.gutterMobile),
          child: child,
        ),
      ),
    );
  }
}

const _screenTitle = '실시간 버스';

/// 학부모 갈래 — 자녀가 여럿이면 하나를 골라야 한다(`home_screen.dart`
/// `_ParentSection` 과 같은 `selectedStudentIdProvider` 를 공유해, 홈에서
/// 고른 자녀가 이 화면에도 그대로 이어진다).
class _ParentLiveMap extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(myStudentsProvider);

    return studentsAsync.when(
      loading: () =>
          const _PlainPage(child: Center(child: CircularProgressIndicator())),
      error: (error, stack) => const _PlainPage(
        child: AlertBanner(tone: AlertTone.missed, body: '자녀 목록을 불러오지 못했습니다'),
      ),
      data: (students) {
        if (students.isEmpty) {
          return _PlainPage(
            child: EmptyState(
              title: '연결된 자녀가 없습니다',
              body: '자녀 연결을 먼저 진행해 주세요',
              action: BaraedaButton(
                label: '자녀 연결하기',
                onPressed: () => context.push(AppRoutes.childLink),
              ),
            ),
          );
        }

        final selectedId = watchSelectedStudentId(ref, students);
        final selected = students.firstWhere(
          (student) => student.studentId == selectedId,
        );

        return _LiveMapBody(
          studentId: selectedId,
          studentName: selected.name,
          switcher: StudentSwitcher(students: students, selectedId: selectedId),
        );
      },
    );
  }
}

/// 학생 갈래 — 본인 `student_id` 하나만 쓴다(조회 전용).
class _StudentLiveMap extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentIdAsync = ref.watch(myStudentIdProvider);

    return studentIdAsync.when(
      loading: () =>
          const _PlainPage(child: Center(child: CircularProgressIndicator())),
      error: (error, stack) => const _PlainPage(
        child: AlertBanner(tone: AlertTone.missed, body: '내 정보를 불러오지 못했습니다'),
      ),
      data: (studentId) => studentId == null
          ? const _PlainPage(child: EmptyState(title: '학생 계정 정보가 없습니다'))
          : _LiveMapBody(studentId: studentId),
    );
  }
}

/// 실제 WebSocket 상태를 그리는 자리 — `studentId` 가 정해진 뒤에만 만든다.
///
/// **"데이터 없음"과 "연결 끊김"을 반드시 구분한다**(완료 조건 9) — 구분은 [LiveMapView.resolve] 의 판정
/// 순서가 한다.
///
/// **P1(Ruling 208·349) — WS 로 받은 좌표도 2분이 지나면 유실로 본다.** 연결 자체가 끊기지 않아도 방송만 멈추면
/// (Ruling 349 — 과부하 때 `position` 방송은 버려질 수 있다) 서버가 다시 판정해 줄 기회가 없다 — 그래서 이 화면이
/// 매 빌드마다 `clockProvider` 로 직접 잰다.
///
/// **F1(2026-09-26) — 표시 중인 좌표가 2분을 넘기는 "그 시점"에 화면을 한 번 다시 그린다.** 유실 판정은 매 빌드마다
/// 다시
/// 재는 순수 계산이라 다른 WS 이벤트가 재빌드를 일으켜야만 갱신됐다 — 방송만 끊기고 다른 이벤트도 없는 좁은 경우는
/// 재빌드 계기가 아예 없었다. 주기 폴링 대신 좌표 하나당 1회 예약이면 충분하다.
class _LiveMapBody extends ConsumerStatefulWidget {
  const new({required this.studentId, this.studentName, this.switcher});

  final String studentId;

  /// 학부모는 선택한 자녀 이름, 학생 본인은 `null`(시트 제목이 "내 …" 로 쓴다).
  final String? studentName;

  /// 자녀가 둘 이상일 때만 있다.
  final Widget? switcher;

  @override
  ConsumerState<_LiveMapBody> createState() => _LiveMapBodyState();
}

class _LiveMapBodyState extends ConsumerState<_LiveMapBody> {
  Timer? _staleRebuildTimer;
  DateTime? _scheduledForReceivedAt;

  /// 새 좌표가 오면 다시 예약하고(같은 좌표면 중복 예약하지 않는다), 화면을 떠나면(`dispose`) 취소한다.
  /// 예약 시각은 `now`(`clockProvider`) 기준으로 구한다 — Ruling 208 판정과 같은 시계를 쓴다.
  void _scheduleStaleRebuild(DateTime? receivedAt, DateTime now) {
    if (receivedAt == null) return;
    if (_scheduledForReceivedAt == receivedAt) return;
    _staleRebuildTimer?.cancel();
    _scheduledForReceivedAt = receivedAt;
    final remaining = positionStaleThreshold - now.difference(receivedAt);
    if (remaining <= Duration.zero) return; // 이미 유실 판정을 넘긴 좌표
    _staleRebuildTimer = Timer(remaining, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _staleRebuildTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveMapStateProvider(widget.studentId));
    final now = ref.watch(clockProvider).now();
    final view = LiveMapView.resolve(state, now);

    _scheduleStaleRebuild(
      view.phase == LiveMapPhase.tracking ? view.positionAt : null,
      now,
    );

    return switch (view.phase) {
      LiveMapPhase.absent => _PlainPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?widget.switcher,
            const Expanded(child: EmptyState(title: '오늘은 버스를 이용하지 않습니다')),
          ],
        ),
      ),
      LiveMapPhase.before => LiveMapBefore(
        studentId: widget.studentId,
        view: view,
        studentName: widget.studentName,
        switcher: widget.switcher,
      ),
      _ => _MapPage(
        studentId: widget.studentId,
        studentName: widget.studentName,
        switcher: widget.switcher,
        view: view,
        onRetry: () => ref.invalidate(liveMapStateProvider(widget.studentId)),
      ),
    };
  }
}

/// 전체 화면 지도 + 아래 시트. 지도는 좌표가 있을 때만 그린다 — 없으면 같은 자리에 옅은 면을 둔다
/// (근거 없는 카메라 위치, 예: 학원 좌표를 기본값으로 잡지 않는다).
///
/// **판단 근거 — 지도 SDK 인증 실패를 화면에 직접 보여준다.** `debugPrint` 만으로 두면 사용자가 왜 지도가 안 뜨는지
/// 알 방법이 없어 "빈 화면" 결함처럼 보인다. 원인(도메인 불일치 vs 키 만료)은 SDK 가 던지는 원본 예외로만 전해져
/// 가를 수 없으므로 "지도를 불러오지 못했습니다" 한 줄이고, 이 상태는 WebSocket 연결과 원인이 다른 별개 채널이라
/// 위젯 로컬 상태로 둔다.
class _MapPage extends ConsumerStatefulWidget {
  const new({
    required this.studentId,
    required this.studentName,
    required this.switcher,
    required this.view,
    required this.onRetry,
  });

  final String studentId;
  final String? studentName;
  final Widget? switcher;
  final LiveMapView view;
  final VoidCallback onRetry;

  @override
  ConsumerState<_MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<_MapPage> {
  bool _authFailed = false;

  /// R46 P3 — 버스를 따라가는 중인가. 켜 두면 새 좌표마다 카메라가 버스로 옮겨 가고, 사용자가 손으로 지도를
  /// 움직이면 꺼진다(F05-09 — 2초마다 사용자가 옮긴 지도를 되돌리지 않는다). [버스 위치로] 가 다시 켠다.
  bool _following = true;

  /// 따라가기를 멈춘 순간의 카메라 — 이후 새 좌표가 와도 이 자리에 둔다. [내 승하차지로] 는 이 값을 직접 정한다.
  MapCamera? _pinned;

  /// 바로 앞 빌드가 지도에 준 카메라 — 사용자가 지도를 만지는 순간 이 자리를 고정한다.
  MapCamera? _shown;

  LiveMapView get _view => widget.view;

  /// 이 화면의 노선(§3.10) — 지금 보는 회차의 것을 읽는다(종료된 회차도 그 회차의 노선이다, `Ruling 831`).
  /// 못 받았으면 `null` — 지도는 버스만 그리고 시트는 §3.5 의 이름으로 대신한다.
  RouteDetail? _route() => ref
      .watch(
        routeForRunProvider((studentId: widget.studentId, runId: _view.runId)),
      )
      .value;

  /// 내 승하차지 — [route] 가 준 정류장.
  RouteStop? _myStop(RouteDetail? route) {
    if (route == null) return null;
    for (final stop in route.stops) {
      if (stop.stopId == route.myStopId) return stop;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final loading = _view.phase == LiveMapPhase.loading;
    final ended = _view.phase == LiveMapPhase.ended;
    final route = loading ? null : _route();
    final myStop = _myStop(route);
    final myStopPoint = myStop?.lat != null && myStop?.lng != null
        ? myStop
        : null;
    final overlay = route == null
        ? null
        : RouteMapOverlay.of(
            route,
            idPrefix: 'live-${widget.studentId}',
            ended: ended,
          );
    // 종료 화면은 서버가 끝난 뒤 좌표를 주지 않아 버스가 없다 — 대신 지나온 구간(노선)을 그리고 지도를 거기에 맞춘다.
    final fitRoute = ended && overlay != null && !overlay.isEmpty;
    final bus = _view.position;
    final showMap = !_authFailed && (bus != null || fitRoute);
    final camera = fitRoute
        ? overlay.start
        : bus == null
        ? null
        : (_following ? MapCamera(lat: bus.lat, lng: bus.lng) : _pinned) ??
              MapCamera(lat: bus.lat, lng: bus.lng);
    _shown = camera;
    // 바퀴 단추는 달리는 중에 있고, 신호가 끊겨도 마지막 좌표가 있으면 남긴다(시안 `live-map--lost`).
    final showFabs =
        showMap &&
        bus != null &&
        (_view.phase == LiveMapPhase.tracking ||
            _view.phase == LiveMapPhase.noSignal);
    final destination = tripDestination(
      direction: _view.run?.direction,
      academyName: ref.watch(academyNameProvider).value,
      myStopName: myStop?.name ?? _view.run?.stop.name,
    );

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: showMap && camera != null
                ? MapSurface(
                    camera: camera,
                    markers: [
                      if (bus != null && !fitRoute)
                        MapMarker(
                          id: 'bus-${widget.studentId}',
                          lat: bus.lat,
                          lng: bus.lng,
                          kind: MapMarkerKind.bus,
                        ),
                      ...?overlay?.markers,
                    ],
                    polylines: overlay?.polylines ?? const [],
                    fitToContent: fitRoute,
                    fitPadding: _fitPadding(context),
                    onUserGesture: () {
                      if (!_following) return;
                      setState(() {
                        _following = false;
                        _pinned = _shown;
                      });
                    },
                    onAuthFailed: (exception) {
                      debugPrint('네이버 지도 인증 실패: $exception');
                      if (mounted) setState(() => _authFailed = true);
                    },
                  )
                : ColoredBox(color: colors.surfaceSunken),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _FloatingTop(
              switcher: widget.switcher,
              tag: _topTag(),
              notice: _authFailed
                  ? const AlertBanner(
                      tone: AlertTone.missed,
                      body: '지도를 불러오지 못했습니다',
                    )
                  : null,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AboveSheetRow(
                  staleTag: _staleTag(),
                  fabs: showFabs
                      ? _MapFabs(
                          onBus: () => setState(() {
                            _following = true;
                            _pinned = null;
                          }),
                          onMyStop: myStopPoint == null
                              ? null
                              : () => setState(() {
                                  _following = false;
                                  _pinned = MapCamera(
                                    lat: myStopPoint.lat!,
                                    lng: myStopPoint.lng!,
                                  );
                                }),
                        )
                      : null,
                ),
                if (loading)
                  const MapSheetSkeleton()
                else
                  _Sheet(
                    studentId: widget.studentId,
                    view: _view,
                    studentName: widget.studentName,
                    myStopName: myStop?.name ?? _view.run?.stop.name,
                    destination: destination,
                    onRetry: widget.onRetry,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 종료 화면이 노선에 맞출 때 비울 여백 — 위는 머리줄, 아래는 시트(화면의 약 4할), 왼쪽은 "내 승하차지" 이름표
  /// 폭이다. 이만큼 비우지 않으면 시트가 노선의 끝(학원)을 가린다.
  EdgeInsets _fitPadding(BuildContext context) => EdgeInsets.fromLTRB(
    120,
    140,
    48,
    MediaQuery.sizeOf(context).height * 0.42,
  );

  /// 지도 위 오른쪽 이름표 — 달리는 중 "12:14 기준" · 종료 "운행 종료".
  Widget? _topTag() {
    final at = _view.positionAt;
    return switch (_view.phase) {
      LiveMapPhase.tracking when at != null => BaraedaMapTag(
        label: '${formatClock(at)} 기준',
      ),
      LiveMapPhase.ended => const BaraedaMapTag(label: '운행 종료', live: false),
      _ => null,
    };
  }

  /// 시트 위 왼쪽 앰버 이름표 — 신호 없음 "마지막 확인 위치 · 4분 전" · 연결 끊김 "마지막 갱신 12:11".
  Widget? _staleTag() {
    final at = _view.positionAt;
    return switch (_view.phase) {
      LiveMapPhase.noSignal when _view.staleMinutes != null => BaraedaMapTag(
        label: '마지막 확인 위치 · ${_view.staleMinutes}분 전',
        stale: true,
      ),
      LiveMapPhase.disconnected when at != null => BaraedaMapTag(
        label: '마지막 갱신 ${formatClock(at)}',
        stale: true,
      ),
      _ => null,
    };
  }
}

/// 지도 위쪽에 뜨는 것들 — 머리줄(뒤로 + 제목 알약) · 자녀 알약 · 오른쪽 이름표.
class _FloatingTop extends StatelessWidget {
  const new({required this.switcher, required this.tag, required this.notice});

  final Widget? switcher;
  final Widget? tag;
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppHeader(title: _screenTitle, tone: AppHeaderTone.floating),
        if (switcher != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BaraedaSpacing.space3,
            ),
            child: switcher,
          ),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.all(BaraedaSpacing.space3),
            child: notice,
          ),
        if (tag != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BaraedaSpacing.space3,
            ),
            child: Align(alignment: Alignment.centerRight, child: tag),
          ),
      ],
    );
  }
}

/// 시트 바로 위 한 줄 — 왼쪽 앰버 이름표, 오른쪽 지도 단추 2개(시안 `.p-staletag` · `.p-fabs`).
class _AboveSheetRow extends StatelessWidget {
  const new({required this.staleTag, required this.fabs});

  final Widget? staleTag;
  final Widget? fabs;

  @override
  Widget build(BuildContext context) {
    if (staleTag == null && fabs == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BaraedaSpacing.space3,
        0,
        BaraedaSpacing.space3,
        BaraedaSpacing.space3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [?staleTag, const Spacer(), ?fabs],
      ),
    );
  }
}

class _MapFabs extends StatelessWidget {
  const new({required this.onBus, required this.onMyStop});

  final VoidCallback onBus;
  final VoidCallback? onMyStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        BaraedaMapButton(
          icon: 'bus',
          semanticLabel: '지도를 버스 위치로 옮기기',
          label: '버스 위치로',
          onPressed: onBus,
        ),
        if (onMyStop != null) ...[
          const SizedBox(height: BaraedaSpacing.space2),
          BaraedaMapButton(
            icon: 'map-pin',
            semanticLabel: '지도를 내 승하차지로 옮기기',
            label: '내 승하차지로',
            onPressed: onMyStop,
          ),
        ],
      ],
    );
  }
}

/// 시트 한 벌 — 누구 버스인지 + 상태 칩 → 상태별 안내 띠 → 두 칸 요약 → [노선 자세히 보기].
///
/// **ETA 를 그리지 않는다.** `WsPositionPayload.eta` 필드가 남아 있어도 절대 표시하지 않는다 — API_SPEC
/// §7.1 "학부모·
/// 학생 채널은 ETA 를 절대 받지 않는다"(C-08)와 §3.10 "승하차지별 탑승 인원 · ETA 부재"가 명시적으로 금지한다.
/// 운행 시작·종료에도 인원수를 붙이지 않는다(C-08 · Ruling 335).
class _Sheet extends StatelessWidget {
  const new({
    required this.studentId,
    required this.view,
    required this.studentName,
    required this.myStopName,
    required this.destination,
    required this.onRetry,
  });

  final String studentId;
  final LiveMapView view;
  final String? studentName;
  final String? myStopName;

  /// 이 회차가 가는 곳의 이름(`Ruling 832`) — 이름을 못 얻으면 `null` 이고 문구가 이름 없이 떨어진다.
  final String? destination;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final startedAt = view.startedAt;
    final finishedAt = view.finishedAt;
    final lastSeenAt = view.lastSeenAt;

    final (chipStatus, chipLabel) = switch (view.phase) {
      LiveMapPhase.tracking => (BaraedaStatus.moving, '이동 중'),
      LiveMapPhase.noSignal => (BaraedaStatus.idle, '신호 없음'),
      LiveMapPhase.ended => (BaraedaStatus.idle, '종료'),
      LiveMapPhase.disconnected when view.forbidden => (
        BaraedaStatus.idle,
        '볼 수 없음',
      ),
      _ => (BaraedaStatus.idle, '연결 끊김'),
    };

    final facts = switch (view.phase) {
      LiveMapPhase.ended => <MapSheetFact>[
        if (startedAt != null)
          (value: formatClock(startedAt), caption: '운행 시작'),
        if (finishedAt != null)
          (value: formatClock(finishedAt), caption: '운행 종료'),
      ],
      LiveMapPhase.noSignal => <MapSheetFact>[
        if (lastSeenAt != null)
          (value: formatClock(lastSeenAt), caption: '마지막으로 확인한 시각'),
        if (myStopName != null) (value: myStopName!, caption: '내 승하차지'),
      ],
      _ => <MapSheetFact>[
        if (view.lastStopName != null)
          (
            value: view.lastStopName!,
            caption: view.lastStopArrivedAt == null
                ? '마지막으로 지난 곳'
                : '마지막으로 지난 곳 · ${formatClock(view.lastStopArrivedAt!)}',
          ),
        if (myStopName != null) (value: myStopName!, caption: '내 승하차지'),
      ],
    };

    return MapSheetFrame(
      children: [
        MapSheetWho(
          initial: studentName?.characters.firstOrNull ?? '나',
          title: _title(),
          subtitle: sheetSubtitle(
            ended: view.phase == LiveMapPhase.ended,
            destination: destination,
            startedAt: startedAt,
          ),
          chipLabel: chipLabel,
          chipStatus: chipStatus,
        ),
        ..._notices(),
        if (facts.isNotEmpty) MapSheetFacts(facts: facts),
        BaraedaButton(
          label: '노선 자세히 보기',
          variant: BaraedaButtonVariant.secondary,
          iconEnd: 'chevron-up',
          block: true,
          onPressed: () => context.push(
            AppRoutes.routeDetailFor(studentId: studentId, runId: view.runId),
          ),
        ),
      ],
    );
  }

  /// "하준이 등원 · 2호차" · 학생 본인은 "내 등원 버스 · 2호차". 회차 목록을 못 받으면 방향 없이 호차만 쓴다.
  String _title() {
    final direction = view.run?.direction.label;
    final name = studentName;
    final head = name != null
        ? (direction == null ? name : '$name $direction')
        : (direction == null ? '내 버스' : '내 $direction 버스');
    final bus = view.busNo;
    return bus == null ? head : '$head · $bus';
  }

  /// 상태별 안내 띠. 지연 띠는 ETA 가 아니라 학원이 보낸 지연 알림이다(NTF-07) — `null` 이면 그리지 않는다.
  List<Widget> _notices() {
    final delay = view.delay;
    final finishedAt = view.finishedAt;
    return [
      if (view.phase == LiveMapPhase.disconnected)
        AlertBanner(
          tone: AlertTone.missed,
          title: view.forbidden
              ? WsConnectionNotice.forbiddenTitle
              : '실시간 위치 연결이 끊어졌어요',
          body: view.forbidden ? '이 회차의 위치 정보를 볼 권한이 없습니다' : '네트워크를 확인해 주세요.',
          inlineAction: !view.forbidden,
          // 권한 거절은 다시 해도 같은 결과라 단추를 두지 않는다. 그 외에는 이 자녀의 연결 상태를 새로 만들어
          // (구독·재연결·위치 스냅샷 재조회) 화면을 나갔다 오는 것과 같게 한다(R32 P7).
          action: view.forbidden
              ? null
              : BaraedaButton(
                  label: '다시 시도',
                  size: BaraedaButtonSize.sm,
                  variant: BaraedaButtonVariant.secondary,
                  onPressed: onRetry,
                ),
        ),
      if (view.phase == LiveMapPhase.noSignal)
        const AlertBanner(
          tone: AlertTone.info,
          title: '위치 신호가 끊겼어요',
          body: '신호가 다시 잡히면 자동으로 갱신돼요.',
        ),
      if (view.phase == LiveMapPhase.ended)
        AlertBanner(
          tone: AlertTone.boarded,
          title: '운행이 끝났어요',
          body: endedBody(finishedAt: finishedAt, destination: destination),
        ),
      if (view.phase == LiveMapPhase.tracking) ...[
        if (view.reconnecting)
          const AlertBanner(
            tone: AlertTone.missed,
            body: WsConnectionNotice.reconnectingTitle,
          ),
        if (delay != null) DelayBand(delay: delay, short: true),
        if (view.position == null)
          const WordWrapText('위치 신호 대기 중', style: BaraedaTypography.bodySm),
      ],
    ];
  }
}
