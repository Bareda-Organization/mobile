import 'package:dio/dio.dart';
import 'package:parent_app/features/child_link/domain/link_models.dart';

/// API_SPEC §3.2·§3.3·§3.4.
class LinkApi {
  LinkApi({required this._dio});

  final Dio _dio;

  /// §3.2.
  Future<LinkRequestResult> requestLink(String studentLoginId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/me/students/link-requests',
      data: {'student_login_id': studentLoginId},
    );
    return LinkRequestResult.fromJson(response.data!);
  }

  /// §3.3 — 요청 본문 부재.
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
