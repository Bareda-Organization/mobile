/// `GET`·`PATCH /me/notification-settings` 모델 (API_SPEC §3.14, NTF-07).
///
/// 지연 알림은 설정 항목 자체가 없다(항상 발송) — 이 클래스에 그 필드를
/// 두지 않는다.
class NotificationSettings {
  const new({
    required this.arrive,
    required this.boarding,
    required this.noShow,
  });

  factory fromJson(Map<String, dynamic> json) =>
      NotificationSettings(
        arrive: json['arrive'] as bool,
        boarding: json['boarding'] as bool,
        noShow: json['no_show'] as bool,
      );

  /// 버스 도착 알림.
  final bool arrive;

  /// 등하원(승차·하차·운행 시작) 알림.
  final bool boarding;

  /// 미승차 알림.
  final bool noShow;

  Map<String, dynamic> toJson() => {
    'arrive': arrive,
    'boarding': boarding,
    'no_show': noShow,
  };

  NotificationSettings copyWith({bool? arrive, bool? boarding, bool? noShow}) =>
      NotificationSettings(
        arrive: arrive ?? this.arrive,
        boarding: boarding ?? this.boarding,
        noShow: noShow ?? this.noShow,
      );
}
