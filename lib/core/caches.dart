part of '../core.dart';

class SecureCaches {
  static late Encrypter _encrypter;
  static bool _isInitialized = false;

  static void initialize(String keyString) {
    if (_isInitialized) return;
    final decodedBytes = base64Url.decode(keyString);
    _encrypter = Encrypter(
      AES(Key(Uint8List.fromList(decodedBytes)), mode: AESMode.gcm),
    );
    _isInitialized = true;
  }

  static List<int> encrypt(List<int> rawBytes) {
    final iv = IV.fromSecureRandom(16);
    final encrypted = _encrypter.encryptBytes(rawBytes, iv: iv);
    return iv.bytes + encrypted.bytes;
  }

  static List<int> decrypt(List<int> encryptedWithIv) {
    final iv = IV(Uint8List.fromList(encryptedWithIv.sublist(0, 16)));
    final encryptedData = encryptedWithIv.sublist(16);
    return _encrypter.decryptBytes(
      Encrypted(Uint8List.fromList(encryptedData)),
      iv: iv,
    );
  }
}
