part of '../core.dart';

class SecureCaches {
  static late Encrypter _encrypter;
  static bool _isInitialized = false;

  static late final CacheManager cacheManager;

  static void initialize(String keyString) {
    if (_isInitialized) return;
    final decodedBytes = base64Url.decode(keyString);
    _encrypter = Encrypter(
      AES(Key(Uint8List.fromList(decodedBytes)), mode: AESMode.gcm),
    );
    cacheManager = CacheManager(
      Config(
        'secures',
        stalePeriod: const Duration(days: 7),
        maxNrOfCacheObjects: 100,
        fileService: SecureFileService(encrypt),
      ),
    );
    _isInitialized = true;
  }

  static List<int> encrypt(List<int> rawBytes) {
    final iv = IV.fromSecureRandom(12);
    final encrypted = _encrypter.encryptBytes(rawBytes, iv: iv);
    return iv.bytes + encrypted.bytes;
  }

  static List<int> decrypt(List<int> encryptedWithIv) {
    final iv = IV(Uint8List.fromList(encryptedWithIv.sublist(0, 12)));
    final encryptedData = encryptedWithIv.sublist(12);
    return _encrypter.decryptBytes(
      Encrypted(Uint8List.fromList(encryptedData)),
      iv: iv,
    );
  }

  // 내부적으로 CachedObject touched 프로퍼티에 의해서 연장됨
  static Future<Uint8List> getUint8List({required String url}) async {
    final uri = Uri.parse(url);
    final key = uri.path;
    final cached = await cacheManager.getFileFromCache(key);
    if (cached?.validTill.isAfter(DateTime.now()) ?? false) {
      final encrypted = await cached!.file.readAsBytes();
      return Uint8List.fromList(decrypt(encrypted));
    }
    if (!uri.hasQuery)
      throw AppNetworkException(message: "접근권한이 없습니다.", statusCode: 404);
    final file = await cacheManager.getSingleFile(url, key: key);
    final encrypted = await file.readAsBytes();
    return Uint8List.fromList(decrypt(encrypted));
  }
}

class SecureFileResponse extends FileServiceResponse {
  final Uint8List encryptedBytes;
  final String? eTag;
  final DateTime validTill;
  final String ext;

  SecureFileResponse(this.encryptedBytes, this.eTag, this.validTill, this.ext);

  @override
  Stream<List<int>> get content => Stream.value(encryptedBytes);

  @override
  int get statusCode => 200;
  @override
  int get contentLength => encryptedBytes.length;
  @override
  String get fileExtension => ext;
}

class SecureFileService extends HttpFileService {
  final List<int> Function(List<int>) encrypt;

  SecureFileService(this.encrypt);

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = await super.get(url, headers: headers);
    final chunks = await response.content.toList();
    final bytes = chunks.expand((e) => e).toList();
    final encrypted = encrypt(bytes);
    return SecureFileResponse(
      Uint8List.fromList(encrypted),
      response.eTag,
      response.validTill,
      response.fileExtension,
    );
  }
}
