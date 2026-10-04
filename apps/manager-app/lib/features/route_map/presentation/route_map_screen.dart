import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/map/route_map_view.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/manager_channel_banner.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
import 'package:manager_app/core/ui/map_legend.dart';
import 'package:manager_app/features/emergency/presentation/widgets/emergency_button.dart';
import 'package:manager_app/features/position/presentation/position_transmitter.dart';
import 'package:manager_app/features/route_map/data/models/route_response.dart';
import 'package:manager_app/features/route_map/presentation/route_providers.dart';

/// RouteMapScreen — 실시간 노선 지도(§4.3, M-04·M-09). 버스기사·동승자
/// 둘 다 호출 가능한 API 를 쓰지만 라우팅 진입은 기사(UF-D-02) 몫이다 —
/// 동승자 플로우엔 지도 화면이 없다(USER_FLOWS.md, 확인됨).
///
/// 지도는 운행 화면 가운데 패널과 같은 [RouteMapView] 를 쓴다 — 도로 경로선 · 승하차지 핀 · 기사 단말이
/// 잰 버스 위치(동승자는 없음) · 근사 경로 안내가 두 화면에서 같다(F06-11). 지도 SDK 는 그 뒤의
/// `MapSurface` 에 있어 이 화면은 `flutter_naver_map` 의 타입을 하나도
/// 모른다(F4-B 1단계 공통 규칙 §2).
class RouteMapScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends ConsumerState<RouteMapScreen> {
  String? _mapErrorMessage;

  void _handleMapAuthFailed(Object exception) {
    if (!mounted) return;
    setState(() => _mapErrorMessage = '지도 인증에 실패했습니다 — 잠시 후 다시 시도해 주세요');
  }

  @override
  Widget build(BuildContext context) {
    final runId = ref.watch(selectedRunIdProvider);
    return Scaffold(
      // 지도가 화면 전체를 쓰고 머리줄은 그 위에 뜬다(시안 `route-map`). 비상 단추는 모든 화면에 둔다(M-15).
      extendBodyBehindAppBar: true,
      appBar: const AppHeader(
        title: '노선 지도',
        tone: AppHeaderTone.floating,
        actions: EmergencyButton(),
      ),
      body: runId == null
          ? const Center(child: WordWrapText('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
          : _buildBody(context, runId),
    );
  }

  Widget _buildBody(BuildContext context, String runId) {
    final routeAsync = ref.watch(routeProvider);
    final route = routeAsync.value;
    final padding = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: routeAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: WordWrapText('노선을 불러오지 못했습니다: ${describeError(error)}'),
            ),
            data: _buildMap,
          ),
        ),
        // 머리줄 아래에 겹쳐 뜨는 알림 — routeAsync.when(...) 의 모든 분기 바깥에 둔다. "노선 없음"(정상,
        // stops[] 빈 배열)과 "연결 끊김"(비정상)을 구별해야 한다(ManagerChannelBanner 문서 §15).
        Positioned(
          top: padding.top + BaraedaSpacing.headerHeight + 8,
          left: 16,
          right: 16,
          child: Column(
            children: [
              ManagerChannelBanner(runId: runId),
              if (_mapErrorMessage != null)
                AlertBanner(tone: AlertTone.missed, body: _mapErrorMessage),
            ],
          ),
        ),
        if (route != null && route.stops.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + padding.bottom,
            child: _LegendCard(route: route),
          ),
      ],
    );
  }

  Widget _buildMap(RouteResponse route) {
    if (route.stops.isEmpty) {
      // §4.3 은 "노선 없음" 을 별도 상태로 정의하지 않는다 — stops[] 가
      // 빈 배열인 것도 정상 응답이다(연결 끊김과는 다른 경우 — 그쪽은
      // 위 배너가 맡는다).
      return const Center(child: WordWrapText('표시할 승하차지가 없습니다'));
    }
    return RouteMapView(
      route: route,
      // 기사 단말이 스스로 잰 위치만 있다 — 운행 화면 지도와 같은 값이다(동승자는 null).
      busPosition: ref.watch(
        positionTransmitterProvider.select((s) => s.busPosition),
      ),
      onAuthFailed: _handleMapAuthFailed,
      // 근사 경로 안내는 아래 범례 카드 안에 있다.
      showFallbackNotice: false,
    );
  }
}

/// 아래 범례 카드(시안 `route-map`) — 표식 4종 · 미경유 안내 · 근사 경로 안내 · 지도 선은 안내용이라는 문구.
class _LegendCard extends StatelessWidget {
  const new({required this.route});

  final RouteResponse route;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = BaraedaTypography.caption.copyWith(
      color: colors.textSecondary,
    );
    final body = BaraedaTypography.body.copyWith(
      color: colors.textPrimary,
      height: 1.5,
    );
    final notice = route.skippedNotice;
    return BaraedaCard(
      padding: const EdgeInsets.all(BaraedaSpacing.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              MapLegendItem(
                swatch: MapLegendSwatch(color: colors.textPrimary),
                label: '지난 곳',
                style: caption,
              ),
              MapLegendItem(
                swatch: MapLegendSwatch(color: colors.statusMoving),
                label: '다음',
                style: caption,
              ),
              MapLegendItem(
                swatch: MapLegendSwatch(color: colors.accentPrimary),
                label: '추가',
                style: caption,
              ),
              MapLegendItem(
                swatch: MapLegendSwatch(color: colors.statusMissed, ring: true),
                label: '정차 안 함',
                style: caption,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (notice != null) WordWrapText(notice, style: body),
          if (route.fallbackUsed && route.roadPath.length >= 2)
            const WordWrapText('근사 경로 — 실제 도로와 다를 수 있습니다'),
          WordWrapText('지도 선은 안내용이고, 실제 길은 기사 판단이에요.', style: body),
        ],
      ),
    );
  }
}
