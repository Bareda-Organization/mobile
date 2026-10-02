import 'package:baraeda_core/baraeda_core.dart';
import 'package:dio/dio.dart';
import 'package:parent_app/features/child_link/data/link_api.dart';
import 'package:parent_app/features/child_link/domain/link_models.dart';
import 'package:parent_app/features/child_link/domain/link_repository.dart';

class LinkRepositoryImpl implements LinkRepository {
  const new({required this._linkApi});

  final LinkApi _linkApi;

  @override
  Future<LinkCodeResult> generateLinkCode() =>
      _guard(_linkApi.generateLinkCode);

  @override
  Future<LinkConfirmResult> confirmLink(String code) =>
      _guard(() => _linkApi.confirmLink(code));

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on DioException catch (exception) {
      // Failure 는 의도적으로 Exception/Error 를 상속하지 않는다
      // (auth_repository_impl.dart 와 같은 설계 — dart:core 예외 체계를
      // 흉내 내지 않는다). 이 지점의 `only_throw_errors` 는 예외로 둔다.
      // ignore: only_throw_errors
      throw mapDioExceptionToFailure(exception);
    }
  }
}
