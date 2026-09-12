import 'package:flutter_riverpod/legacy.dart';
import 'package:manager_app/features/drive_mode/data/models/arrive_stop_result.dart';

/// DriveMode 의 §4.5 도착 처리 응답 중 종료 신호(`is_final`·
/// `finish_pending`·`remaining[]`)를 RunEndScreen 으로 넘기는 자리 —
/// §4.10 이 "전용 종료 API 부재" 라고 명시하는 바로 그 값이라, 화면 사이를
/// 라우터 인자가 아니라 provider 로 잇는다(`selected_run_provider.dart`
/// 와 같은 판단, 보고서에 근거 기록).
final StateProvider<ArriveStopResult?> lastArriveResultProvider =
    StateProvider<ArriveStopResult?>((ref) => null);
