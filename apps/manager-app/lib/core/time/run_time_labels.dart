import 'package:intl/intl.dart';
import 'package:manager_app/core/run/run_enums.dart';

final _hhmm = DateFormat('HH:mm');

/// `12:20` — 기기 로컬 시각의 시:분. 서버가 오프셋 달린 시각을 주므로 항상 로컬로 바꿔 쓴다.
String hhmm(DateTime time) => _hhmm.format(time.toLocal());

/// `출발 · 6분 뒤` — 출발 시각이 지났으면 `출발 · 3분 지남`. 60분 이상이면 `1시간 5분`.
String departsInLabel(DateTime depart, DateTime now) {
  final minutes = depart.difference(now).inMinutes;
  final span = _spanLabel(minutes.abs());
  return minutes >= 0 ? '출발 · $span 뒤' : '출발 · $span 지남';
}

String _spanLabel(int minutes) {
  if (minutes < 60) return '$minutes분';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours시간' : '$hours시간 $rest분';
}

/// `등원` · `하원`.
String directionLabel(RunDirection direction) =>
    direction == RunDirection.toAcademy ? '등원' : '하원';
