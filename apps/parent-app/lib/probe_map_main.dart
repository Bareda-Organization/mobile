// F4-B 0단계 탐침 전용 진입점.
//
// `flutter_naver_map` 1.4.4 래퍼가 네이버 클라우드 플랫폼 신규 인증 키
// (`NCP_KEY_ID` 계열)를 실제로 받아 인증에 성공하는지 눈으로 확인하기 위한
// 최소 화면이다. 기존 앱 화면(`main.dart`)은 건드리지 않는다.
//
// 실행: flutter run -t lib/probe_map_main.dart --dart-define=NAVER_MAP_CLIENT_ID=<값>
//
// 판정 기준(문서 §5.4.2):
//   - 화면 하단에 "인증 성공(onMapLoaded)" 이 뜨면 ✅
//   - "인증 실패: <예외>" 가 뜨면 그 예외 이름으로 원인을 가른다(401/429/800)
//   - 아무 것도 뜨지 않으면(무응답) 미확인 — 네트워크 문제와 구별 불가
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

const _clientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var status = '초기화 시작 전';
  Object? authFailure;

  try {
    await FlutterNaverMap().init(
      clientId: _clientId.isEmpty ? null : _clientId,
      onAuthFailed: (ex) {
        authFailure = ex;
        debugPrint('PROBE-AUTH-FAILED: $ex');
      },
    );
    status = 'init() 반환됨 (clientId 길이=${_clientId.length})';
  } on Exception catch (e, st) {
    status = 'init() 에서 예외: $e';
    debugPrint('PROBE-INIT-EXCEPTION: $e\n$st');
  }

  runApp(_ProbeApp(initStatus: status, authFailureRef: () => authFailure));
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp({required this.initStatus, required this.authFailureRef});

  final String initStatus;
  final Object? Function() authFailureRef;

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  String _mapStatus = '지도 로딩 대기 중';
  bool _mapLoaded = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('F4-B 0단계 — 네이버 지도 인증 탐침')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('init 상태: ${widget.initStatus}'),
                  Text('인증 실패 콜백: ${widget.authFailureRef() ?? "(없음)"}'),
                  Text(
                    '지도 상태: $_mapStatus',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _mapLoaded ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: NaverMap(
                onMapReady: (controller) {
                  setState(() => _mapStatus = 'onMapReady 콜백 도달');
                },
                onMapLoaded: () {
                  setState(() {
                    _mapStatus = 'onMapLoaded — 타일 렌더링 성공(긍정 신호)';
                    _mapLoaded = true;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
