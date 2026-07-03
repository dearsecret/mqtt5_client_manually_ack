part of '../core.dart';

enum AppNetworkMethod { GET, POST, PUT, DELETE, PATCH }

class HttpResult<T> {
  final int statusCode;
  final Map<String, String> headers;
  final T? data;
  final String rawBody;

  bool get isSuccess =>
      (statusCode >= 200 && statusCode < 300) || statusCode == 304;
  bool get isNotModified => statusCode == 304;

  HttpResult({
    required this.statusCode,
    required this.headers,
    required this.rawBody,
    this.data,
  });

  String? get errorMessage {
    if (isSuccess) return null;
    try {
      final decoded = jsonDecode(rawBody);
      return decoded['message'] ?? decoded['detail'] ?? decoded['error'];
    } catch (_) {
      return rawBody.length < 100 ? rawBody : "알 수 없는 서버 오류";
    }
  }
}

class AppNetworkUtilities {
  static const authErr = [401, 403];
  static const serverCreated = [200, 201];

  static bool isAuthErr(int? e) => authErr.contains(e);
  static bool onCreated(int? e) => serverCreated.contains(e);

  static String? handleErrorMessage(Object e) {
    return switch (e) {
      FormatException => "데이터 형식이 잘못되었습니다.",
      TimeoutException => "서버 응답이 없습니다. 잠시 후 다시 시도해주세요.",
      TlsException || HandshakeException => "보안 연결에 실패했습니다.",
      AppNetworkException ex => ex.message, // 커스텀 예외 메시지 그대로 전달
      SocketException error when error.isUnreach => "네트워크 연결을 확인해주세요.",
      SocketException => "네트워크 환경이 원활하지 않습니다.",
      _ => "알 수 없는 오류가 발생했습니다.",
    };
  }
}

class AppNetwork {
  AppNetwork._(this._baseUrl);
  final String _baseUrl;
  static AppNetwork? _instance;
  final http.Client _client = http.Client();
  static const maxRetries = 2;

  static const Duration timeout = Duration(seconds: 10);
  static String get baseUrl => instance._baseUrl;
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
  static AppNetwork get instance => _instance!;

  static late Future<String> Function() getAppcheck;
  static late Future<String?> Function() getRefresh;
  static late Future<void> Function(Map<String, dynamic>) putSecure;

  /// 생성 전 할당 필수
  static late String appcheck, fcmToken, device;
  static String? access;

  static Future<void> Function()? catchNetwork;
  static Future<void> Function(Object error)? onError;

  static bool get isLoggedIn => access != null;

  static AppNetwork? init({required String baseUrl}) {
    if (_instance == null) _instance = AppNetwork._(baseUrl);
    return _instance;
  }

  Completer<void>? _refreshCompleter;

  // ------------------------------
  // 인증/기타 필드
  // ------------------------------
  static Uri _buildUri(String path, {Map<String, dynamic>? queryParameters}) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path).replace(
        queryParameters: queryParameters?.map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      );
    } else {
      throw Exception('잘못된 요청입니다.');
    }
  }

  // ------------------------------
  // 공통 요청 처리
  // ------------------------------
  Future<HttpResult<T>> _sendRequest<T>(
    AppNetworkMethod method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    Map<String, dynamic>? queryParameters,
    bool includeFcm = false,
    T Function(dynamic json)? decoder,
  }) async {
    final uri = _buildUri(path, queryParameters: queryParameters);
    try {
      final encodedBody = body != null ? jsonEncode(body) : null;
      Future<http.Response> requestFn() async {
        final h = <String, String>{
          ...defaultHeaders,
          'X-Firebase-AppCheck': appcheck,
          'X-DEVICE-ID': device,
          if (includeFcm) 'X-DEVICE-TOKEN': fcmToken,
          if (access != null) 'Authorization': 'Bearer $access',
        };
        switch (method) {
          case AppNetworkMethod.GET:
            return _client.get(uri, headers: h);
          case AppNetworkMethod.POST:
            return _client.post(uri, headers: h, body: encodedBody);
          case AppNetworkMethod.PUT:
            return _client.put(uri, headers: h, body: encodedBody);
          case AppNetworkMethod.PATCH:
            return _client.patch(uri, headers: h, body: encodedBody);
          case AppNetworkMethod.DELETE:
            return _client.delete(uri, headers: h, body: encodedBody);
        }
      }

      final response = await _requestWithRetry(requestFn).timeout(timeout);
      final raw = response.body;
      final json = raw.isNotEmpty ? jsonDecode(raw) : null;
      final result = HttpResult<T>(
        statusCode: response.statusCode,
        headers: response.headers,
        rawBody: raw,
        data: decoder?.call(json) ?? (json is T ? json : null),
      );
      if (!result.isSuccess)
        throw AppNetworkException(
          message: result.errorMessage ?? '요청이 거절되었습니다. 잠시 후 다시 시도해주세요.',
          statusCode: result.statusCode,
        );
      return result;
    } catch (e) {
      // 파싱 에러 즉, 서버에서 ''가 아닌 "문자열" 날아옴.
      if (e is FormatException) {} // TODO:
      if (onError != null) onError!(e);
      rethrow;
    }
  }

  // ------------------------------
  // 공개 메서드
  // ------------------------------
  Future<HttpResult<T>> get<T>(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    bool includeFcm = false,
    T Function(dynamic json)? decoder,
  }) {
    return _sendRequest<T>(
      AppNetworkMethod.GET,
      path,
      headers: headers,
      queryParameters: queryParameters,
      includeFcm: includeFcm,
      decoder: decoder,
    );
  }

  Future<HttpResult<T>> post<T>(
    String path, {
    Map<String, String>? headers,
    Object? body,
    T Function(dynamic json)? decoder,
    bool includeFcm = false,
  }) => _sendRequest(
    AppNetworkMethod.POST,
    path,
    headers: headers,
    body: body,
    decoder: decoder,
    includeFcm: includeFcm,
  );

  Future<HttpResult<T>> put<T>(
    String path, {
    Map<String, String>? headers,
    Object? body,
    T Function(dynamic json)? decoder,
    bool includeFcm = false,
  }) => _sendRequest(
    AppNetworkMethod.PUT,
    path,
    headers: headers,
    body: body,
    decoder: decoder,
    includeFcm: includeFcm,
  );

  Future<HttpResult<T>> patch<T>(
    String path, {
    Map<String, String>? headers,
    Object? body,
    T Function(dynamic json)? decoder,
    bool includeFcm = false,
  }) => _sendRequest(
    AppNetworkMethod.PATCH,
    path,
    headers: headers,
    body: body,
    decoder: decoder,
    includeFcm: includeFcm,
  );

  Future<HttpResult<T>> delete<T>(
    String path, {
    Map<String, String>? headers,
    Object? body,
    T Function(dynamic json)? decoder,
    bool includeFcm = false,
  }) => _sendRequest(
    AppNetworkMethod.DELETE,
    path,
    headers: headers,
    body: body,
    decoder: decoder,
    includeFcm: includeFcm,
  );

  Future<void> _refreshToken() async {
    if (_refreshCompleter?.isCompleted ?? false)
      return await _refreshCompleter!.future.timeout(timeout);
    _refreshCompleter = Completer<void>();
    try {
      final uri = _buildUri('/auth/refresh');
      appcheck = await getAppcheck();
      final refresh = await getRefresh.call();
      final response = await _client
          .post(
            uri,
            headers: {'X-Device-Id': device, 'X-Firebase-AppCheck': appcheck},
            body: jsonEncode({'refreshToken': refresh}),
          )
          .timeout(timeout);
      final statusCode = response.statusCode;
      if (statusCode == 401) throw AppNetworkException.authErr;
      if (AppNetworkUtilities.onCreated(statusCode))
        await putSecure(jsonDecode(response.body));
      return _refreshCompleter?.complete();
    } catch (e) {
      _refreshCompleter!.completeError(e);
      rethrow;
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() requestFn,
  ) async {
    int retryCount = 0;
    while (true) {
      try {
        final response = await requestFn().timeout(timeout);
        if (response.statusCode >= 200 && response.statusCode < 300)
          return response;
        if (AppNetworkUtilities.isAuthErr(response.statusCode)) {
          if (isLoggedIn) await _refreshToken();
          final retryRes = await requestFn();
          if (AppNetworkUtilities.isAuthErr(retryRes.statusCode))
            return retryRes;
          throw AppNetworkException.authErr;
        }
        if ([502, 503, 504].contains(response.statusCode))
          throw AppNetworkException.serverErr;
        return response;
      } catch (e) {
        if (++retryCount >= maxRetries) rethrow;
        if (e is SocketException && e.isRetryable) continue;
        if (e is AppNetworkException && e.isServerErr) continue;
        rethrow;
      }
    }
  }

  Future<bool> uploadToS3(
    String url,
    Uint8List bytes, {
    String contentType = 'image/jpeg',
  }) async {
    try {
      final uri = Uri.parse(url);
      return await _client
          .put(
            uri,
            body: bytes,
            headers: {
              'Content-Type': contentType,
              'Content-Length': bytes.length.toString(),
            },
          )
          .timeout(const Duration(seconds: 10))
          .then((r) => r.statusCode == 200);
    } catch (e) {
      print('S3 Upload Error: $e');
      return false;
    }
  }
}
