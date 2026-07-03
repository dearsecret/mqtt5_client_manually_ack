part of '../core.dart';

extension SocketExceptionX on SocketException {
  static const retryableCodes = [54, 104, 60, 110, 11];
  static const unreachableCodes = [51, 101, 13];

  bool get isRetryable => retryableCodes.contains(osError?.errorCode);
  bool get isUnreach => unreachableCodes.contains(osError?.errorCode);
}

class AppNetworkException implements HttpException {
  @override
  final String message;
  final int? statusCode;
  final String? code;
  @override
  final Uri? uri;
  const AppNetworkException({
    required this.message,
    this.statusCode,
    this.code,
    this.uri,
  });

  @override
  String toString() => "AppNetworkException: [$statusCode] $message";
  String get displayMessage => message;

  bool get isServerErr => statusCode == 500;
  bool get isSecureErr => statusCode == 403;
  bool get isAuthErr => statusCode == 401;

  static const authErr = AppNetworkException(
    message: '인증 갱신에 실패하였습니다.',
    statusCode: 401,
  );
  static const appcheckErr = AppNetworkException(
    message: '보안 토큰 검증에 실패하였습니다.',
    statusCode: 403,
  );
  static const serverErr = AppNetworkException(
    message: '서버와의 통신이 원활하지 않습니다.',
    statusCode: 500,
  );
}
