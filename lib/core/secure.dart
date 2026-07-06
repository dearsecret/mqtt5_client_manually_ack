part of '../core.dart';

enum AppSecurity {
  id(isProtected: false, hidden: false),
  access(isProtected: false, hidden: false),
  refresh(isProtected: false, hidden: true),
  device(isProtected: true, hidden: false),
  encrypt(isProtected: true, hidden: true);

  final bool isProtected, hidden;
  const AppSecurity({required this.isProtected, required this.hidden});
  bool get canWrite => !isProtected;

  static List<int> get generateRandomKey => Hive.generateSecureKey();
  static String get generateRandStrKey => base64Encode(generateRandomKey);
  static List<int> decode(String strKey) => base64Url.decode(strKey);

  static Set<String> get inputs =>
      AppSecurity.values
          .where((e) => !e.isProtected)
          .map((e) => e.name)
          .toSet();
}

class FSS {
  FSS._();
  static final FSS instance = FSS._();
  static const _maxRetries = 5;
  static Completer<FSS>? _completer;
  static final List<Completer<void>> _queue = [];

  static String get _access => AppSecurity.access.name;
  static String get _refresh => AppSecurity.refresh.name;

  static final StreamController<String?> _controller =
      StreamController<String?>();
  static StreamController<String?> get ctrl => _controller;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<String?> get refreshToken async =>
      _execute(() => _storage.read(key: AppSecurity.refresh.name));

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
        _storage.registerListener(key: _access, listener: _controller.add);
        // final properties = await getUserProperty();
        // if (properties.containsKey(_access))
        //   _controller.add(properties[_access]);
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
  Future<void> saveAll(Map<String, String> data) async {
    final keys = data.keys.toSet();
    final allowed = AppSecurity.values.where((e) => !e.isProtected).toSet();
    if (!allowed.containsAll(keys)) return;
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
  }

  static Future<void> _clear(Map<String, dynamic> data) async {
    try {
      for (var key in data.keys) {
        if (key == _access) continue;
        if (!AppSecurity.values.byName(key).isProtected)
          await _storage.delete(key: _refresh);
      }
      await _storage.delete(key: _access);
    } finally {
      return;
    }
  }

  Future<Map<String, String>> getUserProperty() async {
    final data = await _storage.readAll();
    final storageKeys = data.keys.toSet();
    if (storageKeys.containsAll(AppSecurity.inputs))
      return Map<String, String>.from(data)
        ..removeWhere((k, _) => AppSecurity.values.byName(k).hidden);
    if (storageKeys.contains(_access)) await _clear(data);
    return Map<String, String>.from({
      if (storageKeys.contains(AppSecurity.device.name))
        AppSecurity.device.name: data[AppSecurity.device.name],
    });
  }

  Future<({String? id, String? device, String? acc})> get properties async =>
      await getUserProperty().then(
        (e) => (
          id: e[AppSecurity.id.name],
          device: e[AppSecurity.device.name],
          acc: e[_access],
        ),
      );
}
