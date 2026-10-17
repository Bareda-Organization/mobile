import 'package:baraeda_core/baraeda_core.dart';
import 'package:parent_app/features/child_link/data/link_api.dart';
import 'package:parent_app/features/child_link/domain/link_models.dart';
import 'package:parent_app/features/child_link/domain/link_repository.dart';

class LinkRepositoryImpl implements LinkRepository {
  const new({required this._linkApi});

  final LinkApi _linkApi;

  @override
  Future<LinkCodeResult> generateLinkCode() =>
      guardDio(_linkApi.generateLinkCode);

  @override
  Future<LinkConfirmResult> confirmLink(String code) =>
      guardDio(() => _linkApi.confirmLink(code));
}
