import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

class FSS {
  FSS._();
  static final FSS instance = FSS._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const _keyStorageKey = 'hive_encryption_key';

  Future<List<int>> getHiveKey() async {
    String? keyString = await _storage.read(key: _keyStorageKey);
    if (keyString == null) {
      final key = Hive.generateSecureKey();
      await _storage.write(key: _keyStorageKey, value: base64UrlEncode(key));
      return key;
    }
    return base64Url.decode(keyString);
  }
}
