/// `POST /me/devices` 요청 (API_SPEC §2.11).
class DeviceRegistrationRequest {
  /// [appVersion] 만 선택값.
  const DeviceRegistrationRequest({
    required this.token,
    required this.platform,
    required this.deviceId,
    this.appVersion,
  });

  /// FCM · APNs 단말 토큰.
  final String token;

  /// `android` · `ios` · `web`.
  final String platform;

  /// 같은 기기의 토큰 갱신 시 기존 행을 대체하는 기준값.
  final String deviceId;

  /// 앱 버전.
  final String? appVersion;

  /// 요청 본문으로 직렬화.
  Map<String, dynamic> toJson() => {
    'token': token,
    'platform': platform,
    'device_id': deviceId,
    if (appVersion != null) 'app_version': appVersion,
  };
}

/// `POST /me/devices` 의 `201` 응답.
class DeviceRegistrationResponse {
  /// 필드 2개 전부 서버가 채워 보낸다.
  const DeviceRegistrationResponse({
    required this.deviceId,
    required this.registeredAt,
  });

  /// 응답 본문을 그대로 옮긴다.
  factory DeviceRegistrationResponse.fromJson(Map<String, dynamic> json) =>
      DeviceRegistrationResponse(
        deviceId: json['device_id'] as String,
        registeredAt: DateTime.parse(json['registered_at'] as String),
      );

  /// 등록된 기기 식별자.
  final String deviceId;

  /// 등록 일시.
  final DateTime registeredAt;
}
