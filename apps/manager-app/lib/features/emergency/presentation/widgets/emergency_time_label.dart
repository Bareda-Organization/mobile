import 'package:intl/intl.dart';

/// 비상 화면이 보이는 시각 표기 — 단말 시간대의 `HH:mm:ss`.
String emergencyTimeLabel(DateTime value) =>
    DateFormat('HH:mm:ss').format(value.toLocal());
