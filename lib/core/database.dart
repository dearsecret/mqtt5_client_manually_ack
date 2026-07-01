part of '../core.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  Completer<void>? _initCompleter;

  late final Directory _appDir, _rootCollectionsDir;
  late List<int> _encryptionKey;
  late List<String> _collections;

  Directory get appDirectory => _appDir;
  bool get isCollectionEmpty => _collections.isEmpty;
  List<String> get collectionList => _collections.toList();

  Map<String, BoxCollection> _caches = {};
  Map<String, Map<String, CollectionBox>> _boxes = {};

  /// FSS에서 생성된 키 : await FSS.instance.getEncryptionKey;
  Future<void> initialize(List<int> key, {int retryCount = 0}) async {
    if (_initCompleter?.isCompleted ?? false) return;
    _initCompleter ??= Completer();
    try {
      if (retryCount == 0) _encryptionKey = key;
      await Hive.initFlutter();
      final appDir = await getApplicationDocumentsDirectory();
      _rootCollectionsDir = Directory('${appDir.path}/collections');
      if (!await _rootCollectionsDir.exists())
        await _rootCollectionsDir.create(recursive: true);
      _collections = await getCollectionNames();
      _initCompleter!.complete();
    } catch (e) {
      await Future.delayed(Duration(seconds: ++retryCount));
      if (retryCount < 3) return await initialize(key, retryCount: retryCount);
      _initCompleter!.completeError(e);
      throw Exception("데이터베이스 초기화 실패: $e");
    }
  }

  Future<List<String>> getCollectionNames() async {
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
    _clearMemory();
    if (await _rootCollectionsDir.exists()) {
      await _rootCollectionsDir.delete(recursive: true);
      await _rootCollectionsDir.create();
    }
  }

  void _clearMemory() {
    for (final col in _caches.values) col.close();
    _boxes.clear();
    _caches.clear();
    _initCompleter = null;
  }

  FutureOr<BoxCollection> openCollection(
    String colName,
    Set<String> boxes,
  ) async {
    if (_caches[colName] == boxes) return _caches[colName]!;
    final boxCollection = await BoxCollection.open(
      colName,
      boxes,
      path: _rootCollectionsDir.path,
      key: HiveAesCipher(_encryptionKey),
    );
    if (!_collections.contains(colName)) _collections.add(colName);
    return (_caches..[colName] = boxCollection)[colName]!;
  }

  FutureOr<CollectionBox> openBox(BoxCollection col, String boxName) async {
    if (!col.boxNames.contains(boxName)) throw Exception("잘못된 접근입니다.");
    if (_boxes[col.name]?[boxName] is! CollectionBox) {
      final box = await col.openBox(boxName);
      _boxes.putIfAbsent(col.name, () => {})[boxName] = box;
    }
    return _boxes[col.name]![boxName]!;
  }
}

/// ## 데이터베이스 헬퍼 믹스인
/// 이 믹스인은 [AppDatabase]와 연동하여 컬렉션 및 박스 접근을
/// 타입 안전하게(Type-Safe) 관리할 수 있도록 기능을 제공합니다.
///
/// **사용 예시:**
/// ```dart
/// enum UserBoxes { profile, settings }
///
/// enum MyCollections with AppCollection<UserBoxes> {
///   user(boxTypes: UserBoxes.values)
///   logs(boxTypes: [UserBoxes.profile]);
///
///   final Iterable<UserBoxes> boxTypes;
///   const MyCollections({required this.boxTypes});
/// }
/// ```
mixin AppCollection<T extends Enum> {
  String get name;
  Iterable<T> get boxTypes;
  Set<String> get boxNames => boxTypes.map((e) => e.name).toSet();

  Future<BoxCollection> get collection async =>
      await AppDatabase.instance.openCollection(name, boxNames);

  /// [boxName]에 해당하는 [CollectionBox]를 엽니다.
  ///
  /// 이미 열려있다면 **캐시된 인스턴스**를 반환하며,
  /// 없으면 `AppDatabase`를 통해 새로 엽니다.
  Future<CollectionBox> open(String boxName) async {
    final col = await collection;
    return await AppDatabase.instance.openBox(col, boxName);
  }

  /// 원자적으로 인수로 받은 함수에 따라 CRUD 를 수행합니다.
  ///
  /// 해당하는 [BoxCollection]가 존재한다면 ***캐시된 인스턴스**를 사용합니다.
  Future<void> run(
    Future Function(BoxCollection) action, {
    bool readOnly = false,
  }) async {
    await collection.then((c) async {
      await c.transaction(
        () async => await action(c),
        boxNames: c.boxNames.toList(),
        readOnly: readOnly,
      );
    });
  }
}
