import 'package:dio/dio.dart';
import 'package:parent_app/features/child_link/domain/link_models.dart';

/// API_SPEC §3.3·§3.4(Ruling 324 — §3.2 연결 요청 단계 폐지).
class LinkApi {
  new({required this._dio});

  final Dio _dio;

  /// §3.3 — 요청 본문 부재. 선행 조건이 없다.
  Future<LinkCodeResult> generateLinkCode() async {
    final response = await _dio.post<Map<String, dynamic>>('/me/link-code');
    return LinkCodeResult.fromJson(response.data!);
  }

  /// §3.4.
  Future<LinkConfirmResult> confirmLink(String code) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/me/students/link',
      data: {'code': code},
    );
    return LinkConfirmResult.fromJson(response.data!);
  }
}
