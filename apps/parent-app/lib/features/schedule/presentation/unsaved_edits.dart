import 'package:flutter/foundation.dart';

/// 일정 화면 안에서 아직 저장·제출하지 않은 입력이 있는 조각을 모은다 — 뒤로가기 확인에 쓴다(R32 P14).
///
/// 조각(주소 편집기 · 변경 신청 패널)이 각자 자기 입력 상태를 알리고, 화면은 하나라도 있으면
/// 나가기 전에 한 번만 묻는다. 조각이 화면에서 사라질 때(자녀 전환 등)는 그 조각의 표시를 지운다.
class UnsavedEdits extends ChangeNotifier {
  final Set<Object> _sources = {};
  bool _disposed = false;

  /// 저장하지 않은 입력이 하나라도 있는가.
  bool get hasAny => _sources.isNotEmpty;

  /// [source] 조각의 입력 상태를 알린다. 바뀐 때만 구독자에게 알린다.
  void mark(Object source, {required bool dirty}) {
    final changed = dirty ? _sources.add(source) : _sources.remove(source);
    if (changed && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
