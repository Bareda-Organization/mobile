import 'package:parent_app/features/child_link/domain/link_models.dart';

/// 화면이 보는 자녀 연결 계약 — §3.3(학생 코드 생성)·§3.4(학부모 코드 확인,
/// Ruling 324 로 §3.2 요청 단계 폐지). 한 인터페이스에 역할 2종의 메서드가
/// 같이 있는 이유는 화면 자체가 역할로 갈리는 한 화면(child_link_screen.dart)
/// 이기 때문 — 실제 호출은 `roleCapabilitiesProvider` 로 가른다.
abstract interface class LinkRepository {
  /// §3.3 — 학생. 선행 조건이 없다.
  Future<LinkCodeResult> generateLinkCode();

  /// §3.4 — 학부모. 서버가 코드를 인증한다(클라이언트 대조 부재).
  Future<LinkConfirmResult> confirmLink(String code);
}
