part of '../core.dart';

enum AppNetworkMethod { GET, POST, PUT, DELETE, PATCH }

extension HttpResponse on http.Response {
  static const authErr = [401, 403];
  bool get isSuccess =>
      (statusCode >= 200 && statusCode < 300) || statusCode == 304;
  bool get isAuthErr => authErr.contains(statusCode);
}

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

class AppNetwork {
  AppNetwork._(this._baseUri);
  final Uri _baseUri;
  static Uri get baseUri => instance._baseUri;
  static AppNetwork? _instance;

  static const version = '/api/v1';
  final http.Client _client = http.Client();
  static const maxRetries = 2;
  static const Duration timeout = Duration(seconds: 10);

  static AppNetwork get instance => _instance!;

  /// 외부 유틸리티로 부터 유효한 토큰을 받습니다.
  late Future<String?> Function() getAppcheck, getRefresh;

  /// Secure Storage에 저장합니다.
  late Future<void> Function(Map<String, String>) tokens;

  /// 에러를 반환 받습니다.
  Future<void> Function(Object error)? onError;

  /// 생성 전 할당 필수
  late String fcmToken, device;
  String? acc, appcheck, id;

  static AppNetwork init({required String baseUrl}) =>
      _instance ??= AppNetwork._(Uri.parse(baseUrl));

  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Map<String, String> _buildHeaders(bool includeFcm) => {
    ...defaultHeaders,
    if (acc == null) 'X-DEVICE-ID': device,
    if (acc != null) 'Authorization': 'Bearer $acc',
    if (appcheck != null) 'X-Firebase-AppCheck': appcheck!,
    if (includeFcm) 'X-DEVICE-TOKEN': fcmToken,
  };

  Completer<void>? _refreshCompleter;

  Uri _buildUri(String path, {Map<String, dynamic>? queryParameters}) {
    if (path.startsWith('http')) {
      final iPath = Uri.parse(path).replace(
        queryParameters: queryParameters?.map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      );
      if (iPath.host != _baseUri.host) throw FormatException("잘못된 요청입니다.");
      return iPath;
    }
    String nPath = path.startsWith('/') ? path : '/$path';
    if (!nPath.startsWith(version)) nPath = '$version$nPath';
    return _baseUri
        .resolve(nPath.startsWith('/') ? nPath.substring(1) : nPath)
        .replace(
          queryParameters: queryParameters?.map(
            (k, v) => MapEntry(k, v.toString()),
          ),
        );
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
    try {
      final encodedBody = body != null ? jsonEncode(body) : null;
      Future<http.Response> requestFn() async {
        final uri = _buildUri(path, queryParameters: queryParameters);
        final h = _buildHeaders(includeFcm);
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
      // if (e is FormatException) {} // TODO:
      if (onError != null) onError!(e);
      rethrow;
    }
  }

  Future<void> refreshes() async {
    if (_refreshCompleter?.isCompleted ?? false)
      return await _refreshCompleter!.future.timeout(timeout);
    _refreshCompleter = Completer<void>();
    try {
      final uri = _buildUri('/auth/refresh');
      final token = await getAppcheck();
      final refresh = await getRefresh();
      if (token == null) throw AppNetworkException.appcheckErr;
      if (refresh == null) throw AppNetworkException.authErr;
      final response = await _client
          .post(
            uri,
            headers: {'X-Device-Id': device, 'X-Firebase-AppCheck': token},
            body: jsonEncode({'refresh': refresh}),
          )
          .timeout(timeout);
      final statusCode = response.statusCode;
      if (statusCode == 401) throw AppNetworkException.authErr;
      if (response.isSuccess)
        await tokens(
          Map<String, String>.from(jsonDecode(response.body)),
        ).then((_) => appcheck = token);
      _refreshCompleter?.complete();
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
        if (response.isSuccess) return response;
        if (response.isAuthErr && acc != null) {
          await refreshes();
          final reRes = await requestFn().timeout(timeout);
          if (reRes.isSuccess) return reRes;
        }
        throw AppNetworkException.unknownErr;
      } catch (e) {
        if (++retryCount >= maxRetries) rethrow;
        if (e is SocketException && e.isRetryable) continue;
        if (e is AppNetworkException && e.isServerErr) continue;
        rethrow;
      }
    }
  }

  // ------------------------------
  // 공개 메서드
  // ------------------------------
  Future<HttpResult<T>> request<T>(
    AppNetworkMethod method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool includeFcm = false,
    T Function(dynamic)? decoder,
  }) => _sendRequest<T>(
    method,
    path,
    body: body,
    queryParameters: query,
    includeFcm: includeFcm,
    decoder: decoder,
  );

  Future<bool> uploadToS3(
    String url,
    Uint8List bytes, {
    String contentType = 'image/jpeg',
  }) async {
    return await _client
        .put(
          Uri.parse(url),
          body: bytes,
          headers: {
            'Content-Type': contentType,
            'Content-Length': bytes.length.toString(),
          },
        )
        .timeout(const Duration(seconds: 10))
        .then((r) => r.statusCode == 200);
  }
}
