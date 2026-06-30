part of '../core.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  late final Directory _appDir, _rootCollectionsDir;
  late List<int> _encryptionKey;
  late List<String> _collections;
  Completer<void>? _initCompleter;

  Directory get appDirectory => _appDir;
  bool get isCollectionEmpty => _collections.isEmpty;
  List<String> get collectionList => _collections;

  /// FSS에서 생성된 키 : await FSS.instance.getEncryptionKey;
  Future<void> initialize(List<int> key, {int retryCount = 0}) async {
    if (_initCompleter?.isCompleted ?? false) return;
    _initCompleter ??= Completer();
    try {
      if (retryCount == 0) {
        _encryptionKey = key;
      } else {
        await Future.delayed(Duration(seconds: retryCount));
      }
      await Hive.initFlutter();
      final appDir = await getApplicationDocumentsDirectory();
      _rootCollectionsDir = Directory('${appDir.path}/collections');
      if (!await _rootCollectionsDir.exists()) {
        await _rootCollectionsDir.create(recursive: true);
        _collections = [];
      } else {
        _collections = await getExistingCollectionNames();
      }
      _initCompleter!.complete();
    } catch (e) {
      // 4. 재시도 로직
      if (retryCount < 3) {
        return await initialize(key, retryCount: retryCount + 1);
      }
      _initCompleter!.completeError(e);
      throw Exception("데이터베이스 초기화 실패: $e");
    }
  }

  Future<BoxCollection> openCollection(
    String colName,
    Set<String> boxes,
  ) async {
    final colPath = '${_rootCollectionsDir.path}/$colName';
    await Directory(colPath).create(recursive: true);
    return await BoxCollection.open(
      colName,
      boxes,
      path: colPath,
      key: HiveAesCipher(_encryptionKey),
    );
  }

  Future<List<String>> getExistingCollectionNames() async {
    final dir = _rootCollectionsDir;
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<Directory>()
        .map((dir) => dir.path.split('/').last)
        .toList();
  }

  Future<List<String>> getBoxesInCollection(String colName) async {
    final colDir = Directory('${_rootCollectionsDir.path}/$colName');
    if (!await colDir.exists()) return [];
    return colDir
        .listSync()
        .where((entity) => entity is File && entity.path.endsWith('.hive'))
        .map((entity) => entity.uri.pathSegments.last.replaceAll('.hive', ''))
        .toList();
  }

  Future<void> resetAll() async {
    if (await _rootCollectionsDir.exists()) {
      await _rootCollectionsDir.delete(recursive: true);
      await _rootCollectionsDir.create();
    }
  }
}
