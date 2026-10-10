import 'package:baraeda_core/baraeda_core.dart';
import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parent_app/app/app_routes.dart';
import 'package:parent_app/app/di.dart';
import 'package:parent_app/core/auth/academy_contact.dart';
import 'package:parent_app/core/auth/auth_providers.dart';
import 'package:parent_app/core/map/map_surface.dart';
import 'package:parent_app/core/refresh/visible_poller.dart';
import 'package:parent_app/core/routes/presentation/route_map_overlay.dart';
import 'package:parent_app/core/routes/presentation/route_providers.dart';
import 'package:parent_app/core/runs/domain/bus_position.dart';
import 'package:parent_app/core/runs/domain/student_run.dart';
import 'package:parent_app/core/runs/presentation/run_display.dart';
import 'package:parent_app/core/ui/delay_band.dart';
import 'package:parent_app/features/home/presentation/widgets/academy_phone_card.dart';
import 'package:parent_app/features/live_map/domain/live_map_status.dart';
import 'package:parent_app/features/live_map/presentation/live_map_view.dart';

/// 홈 지도 미리보기를 다시 읽는 간격 — `API_SPEC §3.11` · `Ruling 821`.
///
/// 홈은 **WebSocket 을 구독하지 않는다.** WebSocket 팬아웃은 부하 여유가 가장 얇은 갈래라 홈 진입자 전원을
/// 구독시키지 않고, 이 엔드포인트를 30초마다 다시 읽는다. 구독은 전체 지도 화면(`LiveMapScreen`)에서만 한다.
const Duration busPreviewInterval = Duration(seconds: 30);

/// 학생 한 명의 §3.11 스냅샷. 오늘 그 학생의 회차가 없으면(`404 RUN_NOT_FOUND`) `null` 이다.
// ignore: specify_nonobvious_property_types
final homeBusPositionProvider = FutureProvider.autoDispose
    .family<BusPosition?, String>((ref, studentId) async {
      // F05-01 — 계정이 바뀌면(로그아웃 = 역할 null) 앞 계정의 캐시를 버린다.
      ref.watch(currentUserRoleProvider);
      try {
        return await ref
            .watch(busPositionRepositoryProvider)
            .getBusPosition(studentId);
      } on ApiFailure catch (failure) {
        if (failure.statusCode == 404) return null;
        rethrow;
      }
    });

/// 홈의 자녀 카드 — 누구 버스인지 · 상태 칩 · 지도 미리보기 · 마지막으로 지난 곳 · 내 승하차지.
///
/// 지도 미리보기는 §3.11 REST 를 [busPreviewInterval] 마다 다시 읽는 것이 전부다(위 상수 문서).
/// 앱이 백그라운드이거나 다른 화면이 홈 위에 있으면 멈추고, 돌아오면 바로 한 번 읽는다(`VisiblePoller`).
class HomeBusPreview extends ConsumerStatefulWidget {
  const new({
    required this.studentId,
    required this.studentName,
    this.runs = const [],
    super.key,
  });

  final String studentId;
  final String studentName;

  /// 오늘 회차 — 방향(`등원`) · 내 승하차지 이름을 여기서 찾는다.
  final List<StudentRun> runs;

  @override
  ConsumerState<HomeBusPreview> createState() => _HomeBusPreviewState();
}

class _HomeBusPreviewState extends ConsumerState<HomeBusPreview> {
  late final VisiblePoller _poller = VisiblePoller(
    interval: busPreviewInterval,
    onTick: _reload,
    isCovered: () => isCoveredFrom(context, {AppRoutes.home}),
  );

  @override
  void initState() {
    super.initState();
    _poller.start();
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  /// 화면을 스피너로 바꾸지 않고(무효화는 옛 값을 유지한 채 다시 받는다) 서버 값으로 갈아 끼운다.
  void _reload() => ref.invalidate(homeBusPositionProvider(widget.studentId));

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(homeBusPositionProvider(widget.studentId));

    return positionAsync.when(
      // 갱신이 실패해도 마지막으로 받은 값을 지우지 않는다 — 엘리베이터·지하철에서 카드가 사라지지 않게.
      skipError: true,
      loading: () => const _PreviewSkeleton(),
      error: (error, stack) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AlertBanner(
            tone: AlertTone.missed,
            body: '버스 위치를 불러오지 못했어요',
            inlineAction: true,
            action: BaraedaButton(
              label: '다시 시도',
              size: BaraedaButtonSize.sm,
              variant: BaraedaButtonVariant.secondary,
              onPressed: _reload,
            ),
          ),
          // 위치를 못 받아도 급한 사람이 갈 곳이 있다 — 번호를 줄 때만 나온다(A11 · Ruling 827).
          if (phoneNumberOf(ref.watch(savedAcademyContactProvider).value)
              case final phone?) ...[
            const SizedBox(height: BaraedaSpacing.space3),
            AcademyPhoneCard(phone: phone),
          ],
        ],
      ),
      data: (position) => position == null
          ? const _NoRunToday()
          : _PreviewBody(
              studentId: widget.studentId,
              studentName: widget.studentName,
              position: position,
              run: widget.runs
                  .where((r) => r.runId == position.runId)
                  .firstOrNull,
            ),
    );
  }
}

class _PreviewSkeleton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '버스 위치를 불러오는 중',
      child: const BaraedaSkeleton(height: 280, radius: 16),
    );
  }
}

/// 오늘 그 학생의 회차가 없다 — 지도 카드를 그릴 근거가 없어 아무것도 그리지 않는다.
/// 아래 회차 목록이 "오늘 예정된 회차가 없습니다" 를 이미 말하므로 같은 안내를 두 번 쓰지 않는다
/// (시뮬레이터에서 두 안내가 겹쳐 보였다).
class _NoRunToday extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _PreviewBody extends ConsumerWidget {
  const new({
    required this.studentId,
    required this.studentName,
    required this.position,
    required this.run,
  });

  final String studentId;
  final String studentName;
  final BusPosition position;
  final StudentRun? run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final delay = position.delay;
    final lat = position.lat;
    final lng = position.lng;
    final received = position.receivedAt;
    final direction = run?.direction.label;
    final stop = position.currentStopName;
    final arrived = position.currentStopArrivedAt;
    final chip = _chip(ref.watch(clockProvider).now());

    // 지금 보는 회차의 노선(§3.10)에서 표시 범위 승하차지 번호와 경로선을 얹는다(`Ruling 831`). 못 받으면 버스만
    // 그린다 — 미리보기에 오류 띠를 더하지 않는다.
    final route = ref
        .watch(
          routeForRunProvider((studentId: studentId, runId: position.runId)),
        )
        .value;
    final ended = position.runStatus == RunStatus.finished;
    final overlay = route == null
        ? null
        : RouteMapOverlay.of(
            route,
            idPrefix: 'preview-$studentId',
            ended: ended,
          );
    // 끝난 회차는 서버가 좌표를 주지 않아 버스가 없다 — 지나온 구간(노선)에 맞춰 그린다.
    // 출발 전 회차도 좌표가 없다 — 빈 면으로 두지 않고 노선을 미리 그린다(Ruling 842).
    final hasBus = lat != null && lng != null;
    final fitRoute = (ended || !hasBus) && overlay != null && !overlay.isEmpty;
    final routeCamera = fitRoute ? overlay.start : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BaraedaCard(
          highlight: true,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(BaraedaSpacing.cardPadding),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [studentName, ?direction, '버스'].join(' '),
                            maxLines: 2,
                            style: BaraedaTypography.body.copyWith(
                              fontWeight: BaraedaFontWeight.bold,
                            ),
                          ),
                          Text(
                            position.busNo,
                            style: BaraedaTypography.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    BaraedaStatusPill(status: chip.status, label: chip.label),
                  ],
                ),
              ),
              SizedBox(
                height: 180,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: routeCamera != null || (lat != null && lng != null)
                          ? MapSurface(
                              camera:
                                  routeCamera ??
                                  MapCamera(lat: lat!, lng: lng!),
                              markers: [
                                if (lat != null && lng != null && !fitRoute)
                                  MapMarker(
                                    id: 'preview-bus-$studentId',
                                    lat: lat,
                                    lng: lng,
                                    kind: MapMarkerKind.bus,
                                  ),
                                ...?overlay?.markers,
                              ],
                              polylines: overlay?.polylines ?? const [],
                              fitToContent: fitRoute,
                            )
                          : ColoredBox(color: colors.statusIdleSoft),
                    ),
                    // 받은 위치가 없는데 "기준" 시각을 보이면 거짓 정보다(P8).
                    if (received != null)
                      Positioned(
                        top: BaraedaSpacing.space2,
                        right: BaraedaSpacing.space2,
                        child: BaraedaMapTag(
                          label: '${formatClock(received)} 기준',
                        ),
                      ),
                    Positioned(
                      right: BaraedaSpacing.space2,
                      bottom: BaraedaSpacing.space2,
                      child: BaraedaMapButton(
                        icon: 'map-pin',
                        semanticLabel: '전체 지도 열기',
                        onPressed: () => context.push(AppRoutes.liveMap),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(BaraedaSpacing.cardPadding),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _StopCell(
                          title: stop ?? '아직 지난 곳이 없어요',
                          caption: arrived == null
                              ? '마지막으로 지난 곳'
                              : '마지막으로 지난 곳 · ${formatClock(arrived)}',
                        ),
                      ),
                      VerticalDivider(color: colors.borderSubtle, width: 24),
                      Expanded(
                        child: _StopCell(
                          title: run?.stop.name ?? '-',
                          caption: '내 승하차지',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 지연 띠 — ETA 가 아니라 학원이 보낸 지연 알림이다(NTF-07). `null` 이면 그리지 않는다.
        if (delay != null) ...[
          const SizedBox(height: BaraedaSpacing.space3),
          DelayBand(delay: delay),
        ],
      ],
    );
  }

  /// 칩은 전체 지도와 같은 판정(`LiveMapView.resolve` — 신호 유실 2분 · 종료 · 미등원)을 따른다.
  /// 출발 전(`before`)은 지도 시트가 칩을 그리지 않는 모양이라 회차 상태로 정한다.
  ({BaraedaStatus status, String label}) _chip(DateTime now) {
    final view = LiveMapView.resolve(
      LiveMapState(
        connection: LiveMapConnection.connected,
        restPosition: AsyncValue.data(position),
        isAbsent: run?.riderStatus == RiderStatus.absent,
        run: run,
      ),
      now,
    );
    return switch (view.phase) {
      LiveMapPhase.absent => (status: BaraedaStatus.idle, label: '미등원'),
      LiveMapPhase.before => switch (position.runStatus) {
        RunStatus.confirmed => (status: BaraedaStatus.boarded, label: '확정'),
        _ => (status: BaraedaStatus.waiting, label: '운행 전'),
      },
      _ => view.chip,
    };
  }
}

class _StopCell extends StatelessWidget {
  const new({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: BaraedaTypography.body.copyWith(
            fontWeight: BaraedaFontWeight.bold,
          ),
        ),
        Text(
          caption,
          style: BaraedaTypography.caption.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
