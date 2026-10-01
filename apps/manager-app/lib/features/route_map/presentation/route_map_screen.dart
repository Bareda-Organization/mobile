import 'package:baraeda_ui/baraeda_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:manager_app/core/map/route_map_view.dart';
import 'package:manager_app/core/network/failure_messages.dart';
import 'package:manager_app/core/run/manager_channel_banner.dart';
import 'package:manager_app/core/run/selected_run_provider.dart';
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
  const RouteMapScreen({super.key});

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
      appBar: AppBar(title: const Text('노선 지도')),
      body: runId == null
          ? const Center(child: WordWrapText('선택된 운행이 없습니다 — 홈에서 운행을 선택하세요'))
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
            error: (error, _) => Center(
              child: WordWrapText('노선을 불러오지 못했습니다: ${describeError(error)}'),
            ),
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
      return const Center(child: WordWrapText('표시할 승하차지가 없습니다'));
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
          child: RouteMapView(
            route: route,
            // 기사 단말이 스스로 잰 위치만 있다 — 운행 화면 지도와 같은 값이다(동승자는 null).
            busPosition: ref.watch(
              positionTransmitterProvider.select((s) => s.busPosition),
            ),
            onAuthFailed: _handleMapAuthFailed,
          ),
        ),
      ],
    );
  }
}
