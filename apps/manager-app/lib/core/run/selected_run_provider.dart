import 'package:flutter_riverpod/legacy.dart';

/// 화면 간 회차 선택 상태 — ManagerHome 에서 운행 카드를 고르면 이 값을
/// 채우고, DriveMode·StopRoster·DelayScreen·RunEndScreen 은 이 값을 읽어
/// `runId` 를 얻는다.
///
/// 라우트 경로에 `:runId` 파라미터를 넣는 대신 이 provider 를 쓴 이유 —
/// 이번 라운드 5화면 전부가 "현재 선택된 회차 하나" 를 다루고 화면 사이
/// 이동이 항상 ManagerHome 을 거쳐 일어나는 흐름이라, 경로 파라미터마다
/// 화면이 `GoRouterState.pathParameters` 를 다시 파싱하게 하는 것보다 단일
/// 상태를 공유하는 편이 간단하다(판단 근거, 보고서 참고). 여러 회차를
/// 동시에 여러 탭으로 열어야 하는 요구가 생기면 그때 경로 파라미터로
/// 바꾼다.
final StateProvider<String?> selectedRunIdProvider = StateProvider<String?>(
  (ref) => null,
);
