import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/map/map_surface.dart';
import 'package:manager_app/core/run/manager_channel_banner.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

/// RouteMapScreen — 실시간 노선 지도(§4.3, M-04·M-09). 버스기사·동승자
/// 둘 다 호출 가능한 API 를 쓰지만 라우팅 진입은 기사(UF-D-02) 몫이다 —
/// 동승자 플로우엔 지도 화면이 없다(USER_FLOWS.md, 확인됨).
///
/// 지도 SDK 는 [MapSurface] 뒤에 있다 — 이 화면은 `flutter_naver_map` 의
/// 타입을 하나도 모른다(F4-B 1단계 공통 규칙 §2).
///
/// **경로선을 안 그리는 이유** — §4.3 은 "미경유는 표시만 — 재최적화 ·
/// ETA 재계산 · 경로 안내 부재"(C-05)라고 명시한다. 즉 이 화면은
/// 승하차지 지점만 찍고, 지점을 잇는 선·최적 경로는 그리지 않는다 —
/// 그릴 근거가 사양에 없다.
class RouteMapScreen extends ConsumerStatefulWidget {
  const RouteMapScreen({super.key});

  @override
  ConsumerState<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends ConsumerState<RouteMapScreen> {
  String? _mapErrorMessage;

  void _handleMapAuthFailed(Object exception) {
    if (!mounted) return;
    setState(() => _mapErrorMessage = '지도 인증에 실패했습니다: $exception');
  }

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('노선 지도')),
      body: runId == null
          ? const Center(child: Text('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
          : _buildBody(context, runId),
    );
  }

  Widget _buildBody(BuildContext context, String runId) {
    final routeAsync = ref.watch(routeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // routeAsync.when(...) 의 모든 분기 바깥 — "노선 없음"(정상,
              // stops[] 빈 배열)과 "연결 끊김"(비정상)을 구별해야 한다
              // (ManagerChannelBanner 문서 §15, DriveModeScreen 과 같은
              // 관례).
              ManagerChannelBanner(runId: runId),
              if (_mapErrorMessage != null) ...[
                AlertBanner(tone: AlertTone.missed, body: _mapErrorMessage),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        Expanded(
          child: routeAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: Text('노선을 불러오지 못했습니다: $error')),
            data: _buildMap,
          ),
        ),
      ],
    );
  }

  Widget _buildMap(RouteResponse route) {
    if (route.stops.isEmpty) {
      // §4.3 은 "노선 없음" 을 별도 상태로 정의하지 않는다 — stops[] 가
      // 빈 배열인 것도 정상 응답이다(연결 끊김과는 다른 경우 — 그쪽은
      // 위 배너가 맡는다).
      return const Center(child: Text('표시할 승하차지가 없습니다'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (route.skippedNotice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AlertBanner(tone: AlertTone.info, body: route.skippedNotice),
          ),
        Expanded(
          child: MapSurface(
            camera: _cameraFor(route),
            markers: _markersFor(route),
            onAuthFailed: _handleMapAuthFailed,
          ),
        ),
      ],
    );
  }

  /// 지도 중심 — `current_stop` 우선, 없으면 `next_stop`, 그마저 없으면
  /// 노선의 첫 승하차지. §4.3 은 카메라 위치를 정하지 않는다(경로 안내
  /// 자체가 범위 밖) — "지금 기사가 봐야 할 지점" 을 중심에 두는 것은
  /// 사양이 아니라 이 화면의 판단이다.
  MapCamera _cameraFor(RouteResponse route) {
    final anchor = route.currentStop ?? route.nextStop ?? route.stops.first;
    return MapCamera(lat: anchor.lat, lng: anchor.lng, zoom: 15);
  }

  /// 마커 — `stops[]` 전부를 [MapMarkerKind.stop] 으로 찍는다.
  ///
  /// ⚠ **`current_stop` 에 [MapMarkerKind.bus] 마커를 얹지 않는다**
  /// (F4-B 2단계 M2 판정 — 1단계가 근사로 찍었던 것을 되돌림). 이유는
  /// 이름표와 실제 값의 불일치다 — [MapMarkerKind.bus] 의 계약은
  /// "운행 중인 버스의 현재 위치"([MapMarkerKind] 문서, `map_surface.dart`)
  /// 인데, `current_stop` 은 백엔드에서 "`arrivedAt` 이 있는 것 중 `seq`
  /// 최댓값" — 즉 **방금 들른 승하차지**로 계산된다(`RunRouteQueryService.
  /// buildFromVersion`), 실시간 GPS 가 전혀 아니다. 이 화면이 구독하는
  /// `/ws/manager/runs/{id}` 채널에도 `position` 필드가 없어(§7) 실시간
  /// 좌표를 받을 길 자체가 없다.
  ///
  /// 이 화면의 사용자는 기사·동승자 자신이다 — 자기가 탄 버스의 위치를
  /// "버스" 라는 이름표로 잘못 보여주면, 방금 지나온 지점을 지금 위치로
  /// 오인해 다음 승하차지까지 남은 거리를 잘못 판단할 수 있다. 근거
  /// 확인 — `docs/USER_FLOWS.md` 의 기사·동승자 플로우(`UF-D-02`·
  /// `UF-D-03`)는 이 화면에 "버스 마커" 를 요구하지 않고, 실시간 버스
  /// 위치 마커를 쓰는 유일한 플로우(`UF-P-07`)는 학부모·학생 전용
  /// 엔드포인트(`GET /students/{id}/bus-position`)를 쓴다 — **이
  /// 화면(기사·동승자)에 버스 마커를 둘 근거가 없다.**
  ///
  /// [MapMarkerKind.student] 는 이 응답에 개별 학생 좌표가 없어 쓰지
  /// 않는다 — `student_count` 는 숫자일 뿐 위치 정보가 아니다.
  List<MapMarker> _markersFor(RouteResponse route) {
    return [
      for (final stop in route.stops)
        MapMarker(
          id: stop.stopId,
          lat: stop.lat,
          lng: stop.lng,
          kind: MapMarkerKind.stop,
        ),
    ];
  }
}
