// F4-B 2단계 목표 6 전용 탐침 진입점.
//
// 마커 수십 개를 동시에 2초 간격으로 움직여, 프레임 타이머 기반 보간이
// 실제 기기(시뮬레이터)에서 눈으로 봐도 매끄러운지 확인하기 위한 최소
// 화면이다. `probe_map_main.dart`(인증 전용 탐침)는 건드리지 않는다.
//
// 실행: flutter run -t lib/probe_marker_load_main.dart \
//         --dart-define=NAVER_MAP_CLIENT_ID=<값>
//
// 화면 우상단 숫자 버튼으로 마커 개수를 수동으로도 바꿀 수 있고, 켜자마자
// 25초 간격으로 10 → 30 → 60 → 100 순서로 자동으로 늘어난다(시뮬레이터
// 조작 없이도 실측 가능). 지도 위 왼쪽 위 배지가 현재 개수를 보여준다.
// 눈과 프레임 성능 오버레이(`showPerformanceOverlay`, 실측 후 꺼 둠)로
// 버벅임 여부를 판정한다 — 판정 결과는 report-P2.md 에 남긴다.
// `MapSurface`(공개 계약)만 쓰고 SDK 타입은 여기 나타나지 않는다 —
// `test/architecture/map_port_boundary_test.dart` 의 경계를 그대로 지킨다.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:parent_app/core/map/map_surface.dart';

void main() {
  runApp(const _MarkerLoadProbeApp());
}

class _MarkerLoadProbeApp extends StatelessWidget {
  const _MarkerLoadProbeApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: _MarkerLoadProbeScreen());
  }
}

class _MarkerLoadProbeScreen extends StatefulWidget {
  const _MarkerLoadProbeScreen();

  @override
  State<_MarkerLoadProbeScreen> createState() =>
      _MarkerLoadProbeScreenState();
}

class _MarkerLoadProbeScreenState extends State<_MarkerLoadProbeScreen> {
  // 서울 시청 부근을 중심으로 랜덤하게 흩뿌린다.
  static const _centerLat = 37.5665;
  static const _centerLng = 126.9780;

  int _markerCount = 10;
  Timer? _tick;
  Timer? _autoCycle;
  final _rand = Random(1);
  late List<_ProbeBus> _buses;

  @override
  void initState() {
    super.initState();
    _buses = _makeBuses(_markerCount);
    _startTicking();
    // 시뮬레이터에서 버튼을 직접 누르지 않아도 목표 6 실측(10→30→60→100)을
    // 순서대로 볼 수 있도록 자동으로 개수를 올린다 — 수동 버튼도 그대로
    // 남겨 둔다.
    var step = 0;
    const counts = [10, 30, 60, 100];
    _autoCycle = Timer.periodic(const Duration(seconds: 25), (_) {
      step++;
      if (step >= counts.length) {
        _autoCycle?.cancel();
        return;
      }
      _setCount(counts[step]);
    });
  }

  List<_ProbeBus> _makeBuses(int count) => List.generate(
        count,
        (i) => _ProbeBus(
          id: 'probe-bus-$i',
          lat: _centerLat + (_rand.nextDouble() - 0.5) * 0.06,
          lng: _centerLng + (_rand.nextDouble() - 0.5) * 0.06,
        ),
      );

  void _startTicking() {
    _tick?.cancel();
    // 2단계에서 바꾼 전송 주기(2초)와 같은 간격으로 새 좌표를 흘린다 —
    // 실제 운행 중 수신 패턴과 같은 조건에서 버벅임을 봐야 의미가 있다.
    _tick = Timer.periodic(const Duration(seconds: 2), (_) {
      setState(() {
        for (final bus in _buses) {
          bus
            ..lat += (_rand.nextDouble() - 0.5) * 0.004
            ..lng += (_rand.nextDouble() - 0.5) * 0.004;
        }
      });
    });
  }

  void _setCount(int count) {
    setState(() {
      _markerCount = count;
      _buses = _makeBuses(count);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _autoCycle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('마커 부하 탐침 — 현재 $_markerCount 개'),
        actions: [
          for (final n in [10, 30, 60, 100])
            TextButton(
              onPressed: () => _setCount(n),
              child: Text(
                '$n',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          MapSurface(
            camera:
                const MapCamera(lat: _centerLat, lng: _centerLng, zoom: 12),
            markers: [
              for (final bus in _buses)
                MapMarker(
                  id: bus.id,
                  lat: bus.lat,
                  lng: bus.lng,
                  kind: MapMarkerKind.bus,
                ),
            ],
          ),
          // 스크린샷만으로 현재 개수를 확실히 읽을 수 있도록 큰 배지를
          // 지도 위에 겹쳐 둔다 — 앱바 제목은 버튼에 가려 잘린다.
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_markerCount 개',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProbeBus {
  _ProbeBus({required this.id, required this.lat, required this.lng});

  final String id;
  double lat;
  double lng;
}
