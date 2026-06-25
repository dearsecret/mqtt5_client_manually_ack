import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum SecureKey {
  encrypt(isProtected: true),
  device(isProtected: true),
  access(isProtected: false),
  refresh(isProtected: false);

  final bool isProtected;
  const SecureKey({required this.isProtected});
  bool get canWrite => !isProtected;
}

class SecureUtils {
  SecureUtils._();

  static List<int> get generateRandomKey => Hive.generateSecureKey();
  static String get generateRandStrKey => base64Encode(generateRandomKey);
  static List<int> decode(String strKey) => base64Url.decode(strKey);
}

class FSS {
  FSS._();
  static final FSS instance = FSS._();
  static final List<Completer<void>> _queue = [];
  static String? _cachedAccessToken;

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  bool _isAllowed(String key) =>
      SecureKey.values.any((e) => e.name == key && e.canWrite);

  Future<T> _execute<T>(Future<T> Function() action, {int retryCount = 0}) =>
      _enqueue(() => _runWithRetry(action, retryCount: retryCount));

  Future<void> _executeBatch(
    Map<String, String> data, {
    bool isWrite = true,
  }) async => await Future.wait(
    isWrite
        ? data.entries.map((e) => _storage.write(key: e.key, value: e.value))
        : data.keys.map((key) => _storage.delete(key: key)),
  );

  Future<String?> get getRefreshToken async =>
      _execute(() => _storage.read(key: SecureKey.refresh.name));

  Future<String?> get getAccessToken async {
    if (_cachedAccessToken != null) return _cachedAccessToken;
    return _execute(() async {
      final token = await _storage.read(key: SecureKey.access.name);
      _cachedAccessToken = token;
      return token;
    });
  }

  Future<List<int>> get getEncryptionKey => _getOrInitSecureData(
    SecureKey.encrypt,
    (str) => base64Url.decode(str),
    () => base64UrlEncode(Hive.generateSecureKey()),
  );

  Future<String> get getDeviceId => _getOrInitSecureData(
    SecureKey.device,
    (str) => str,
    () => SecureUtils.generateRandStrKey,
  );

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
        if (attempts >= retryCount) rethrow; // 횟수 초과 시 종료
        attempts++;
        await Future.delayed(initialDelay * (1 << (attempts - 1)));
      }
    }
  }

  Future<T> _getOrInitSecureData<T>(
    SecureKey key,
    T Function(String) decoder,
    String Function() generator,
  ) async {
    return _execute(() async {
      String? storedData = await _storage.read(key: key.name);
      if (storedData == null) {
        final newData = generator();
        await _storage.write(key: key.name, value: newData);
        return decoder(newData);
      }
      return decoder(storedData);
    });
  }

  Future<bool> writeAll(Map<String, String> data, {int retryCount = 0}) async {
    return _execute(() async {
      if (data.keys.any((key) => !_isAllowed(key))) return false;
      return _runWithRetry(() async {
        final backup = await _storage.readAll();
        try {
          await _executeBatch(data, isWrite: true);
          if (data.containsKey(SecureKey.access.name)) {
            _cachedAccessToken = data[SecureKey.access.name];
          }
          return true;
        } catch (e) {
          await _executeBatch(backup, isWrite: true);
          _cachedAccessToken = backup[SecureKey.access.name];
          rethrow;
        }
      }, retryCount: retryCount);
    });
  }

  Future<bool> clearAll({int retryCount = 0}) async {
    return _execute(() async {
      try {
        await _runWithRetry(() async {
          final backup = await _storage.readAll();
          final keysToDelete = Map.fromEntries(
            backup.entries.where(
              (e) =>
                  !SecureKey.values
                      .firstWhere(
                        (s) => s.name == e.key,
                        orElse: () => SecureKey.access,
                      )
                      .isProtected,
            ),
          );

          try {
            await _executeBatch(keysToDelete, isWrite: false);
            _cachedAccessToken = null;
          } catch (e) {
            await _executeBatch(backup, isWrite: true);
            _cachedAccessToken = backup[SecureKey.access.name];
            rethrow;
          }
        }, retryCount: retryCount);
        return true;
      } catch (e) {
        return false;
      }
    });
  }
}
