part of '../core.dart';

enum AppSecurity {
  id(isProtected: false),
  access(isProtected: false),
  refresh(isProtected: false),
  device(isProtected: true),
  encrypt(isProtected: true);

  final bool isProtected;
  const AppSecurity({required this.isProtected});
  bool get canWrite => !isProtected;

  static List<int> get generateRandomKey => Hive.generateSecureKey();
  static String get generateRandStrKey => base64Encode(generateRandomKey);
  static List<int> decode(String strKey) => base64Url.decode(strKey);
}

class FSS {
  FSS._();
  static final FSS instance = FSS._();
  static const _maxRetries = 5;
  static Completer<FSS>? _completer;
  static final List<Completer<void>> _queue = [];

  static String get _access => AppSecurity.access.name;
  static String get _id => AppSecurity.id.name;
  static String get _refresh => AppSecurity.refresh.name;

  static final StreamController _controller = StreamController();
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Stream get stream => _controller.stream;

  Future<String?> get refreshToken async =>
      _execute(() => _storage.read(key: AppSecurity.refresh.name));

  Future<String?> get id async =>
      _execute(() => _storage.read(key: AppSecurity.id.name));

  Future<List<int>> get getEncryptionKey => _getOrInitSecureData(
    AppSecurity.encrypt,
    (str) => base64Url.decode(str),
    () => base64UrlEncode(Hive.generateSecureKey()),
  );

  Future<String> get getDevice => _getOrInitSecureData(
    AppSecurity.encrypt,
    (str) => str,
    () => base64UrlEncode(AppSecurity.generateRandomKey),
  );

  FutureOr<FSS> initialize() async {
    if (_completer?.isCompleted ?? false) return instance;
    if (_completer != null) return await _completer!.future;
    _completer = Completer<FSS>();
    int retryCount = 0;
    while (retryCount < _maxRetries) {
      try {
        _storage.registerListener(
          key: AppSecurity.access.name,
          listener: _controller.add,
        );
        final value = await _storage.read(key: AppSecurity.access.name);
        _controller.add(value);
        _completer?.complete(instance);
        return FSS.instance;
      } catch (e) {
        retryCount++;
        if (retryCount >= _maxRetries) break;
        await Future.delayed(Duration(seconds: retryCount));
      }
    }
    final error = Exception("Initialization failed after $_maxRetries retries");
    _completer!.completeError(error);
    throw error;
  }

  Future<T> _execute<T>(Future<T> Function() action, {int retryCount = 0}) =>
      _enqueue(() => _runWithRetry(action, retryCount: retryCount));

  /// 파이프라인: 선입선출(FIFO) 완벽 보장
  Future<T> _enqueue<T>(Future<T> Function() action) async {
    final completer = Completer<void>();
    final previous = _queue.isNotEmpty ? _queue.last : null;
    _queue.add(completer);
    if (previous != null) await previous.future;
    try {
      return await action();
    } finally {
      completer.complete();
      _queue.remove(completer);
    }
  }

  /// 재시도 엔진: 지수 백오프 기반 최대 retryCount만큼 시도
  Future<T> _runWithRetry<T>(
    Future<T> Function() action, {
    int retryCount = 0,
    Duration initialDelay = const Duration(milliseconds: 200),
  }) async {
    int attempts = 0;
    while (true) {
      try {
        return await action();
      } catch (e) {
        if (attempts >= retryCount) rethrow;
        attempts++;
        await Future.delayed(initialDelay * (1 << (attempts - 1)));
      }
    }
  }

  Future<T> _getOrInitSecureData<T>(
    AppSecurity key,
    T Function(String) decoder,
    String Function() generator,
  ) async {
    return _execute(() async {
      String? storedData = await _storage.read(key: key.name);
      if (storedData != null) return decoder(storedData);
      String newData = generator();
      await _storage.write(key: key.name, value: newData);
      return decoder(newData);
    });
  }

  /// 모든 저장이 성공한 후에 access를 변경하여 Stream에 변경사항을 알립니다.
  FutureOr<bool> saveAll(Map<String, String> data) async {
    final keys = data.keys.toSet();
    final allowed = AppSecurity.values.where((e) => !e.isProtected).toSet();
    if (!allowed.containsAll(keys)) return false;
    final access = data.remove(_access);
    await _enqueue<void>(() async {
      return await _runWithRetry(() async {
        await Future.wait(
          data.entries
              .map((k) => _storage.write(key: k.key, value: k.value))
              .toList(),
        ).then((_) async => await _storage.write(key: _access, value: access));
      }, retryCount: 0);
    });
    return true;
  }

  /// 호출시 서버에서 이미 refresh는 삭제됐으며, access를 지워주는 것만으로도 효괴는 동일함.
  /// access 만 삭제된다면 refresh가 지워지지 않아도 무시해도됨.
  Future<void> clear() async {
    await _storage.delete(key: _access);
    try {
      await _storage.delete(key: _id);
      await _storage.delete(key: _refresh);
    } finally {
      return;
    }
  }

  Future<({String? id, String? access})> getAccessUser() async {
    final data = await _storage.readAll();
    if (data case {'id': final String id, 'access': final String access}) {
      return (id: id, access: access);
    }
    await clear();
    return (id: null, access: null);
  }
}
