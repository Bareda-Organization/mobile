import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'offline_queue_database.g.dart';

/// 오프라인 상태에서 쌓인 승하차 처리 요청 큐 (M-06, API_SPEC §1.7 멱등성).
///
/// 각 행은 재접속 시 그대로 재전송할 요청 하나 — 본문에 실을 `client_key`
/// 를 요청 생성 시점에 미리 발급해 둬서, 큐 재생과 즉시 전송이 서버 입장에서
/// 같은 멱등 키를 쓰게 한다. 실제 재생·전송 로직은 이번 범위가 아니다.
class PendingRequests extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// API_SPEC §1.7 멱등 키 — 단말에서 미리 발급한 UUID.
  TextColumn get clientKey => text()();

  /// 호출할 엔드포인트 경로.
  TextColumn get endpoint => text()();

  /// 요청 본문 (JSON 직렬화된 문자열).
  TextColumn get payload => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [PendingRequests])
class OfflineQueueDatabase extends _$OfflineQueueDatabase {
  OfflineQueueDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'offline_queue.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
