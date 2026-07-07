part of '../core.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  static const _maxRetries = 5;
  Completer<AppDatabase>? _initCompleter;

  late final Directory _appDir, _rootCollectionsDir;
  late List<int> _encryptionKey;
  late List<String> _collections;

  Directory get appDirectory => _appDir;
  bool get isCollectionEmpty => _collections.isEmpty;
  List<String> get collectionList => _collections.toList();

  Map<String, BoxCollection> _caches = {};
  Map<String, Map<String, CollectionBox>> _boxes = {};

  /// FSS에서 생성된 키 : await FSS.instance.getEncryptionKey;
  FutureOr<AppDatabase> initialize(List<int> key) async {
    if (_initCompleter?.isCompleted ?? false) return instance;
    if (_initCompleter != null) return await _initCompleter!.future;
    _initCompleter = Completer<AppDatabase>();

    int retryCount = 0;
    while (retryCount < _maxRetries) {
      try {
        _encryptionKey = key;
        await Hive.initFlutter();
        _appDir = await getApplicationDocumentsDirectory();
        _rootCollectionsDir = Directory('${_appDir.path}/collections');
        if (!await _rootCollectionsDir.exists()) {
          await _rootCollectionsDir.create(recursive: true);
        }
        _collections = await getCollectionNames();
        _initCompleter!.complete(instance);
        return instance;
      } catch (e) {
        retryCount++;
        if (retryCount >= _maxRetries) {
          final error = Exception("데이터베이스 초기화 실패: $e");
          _initCompleter!.completeError(error);
          throw error;
        }
        await Future.delayed(Duration(seconds: retryCount));
      }
    }
    throw Exception("Database initialization unexpected failure.");
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
    if (_caches.containsKey(colName)) return _caches[colName]!;
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

// enum UserBoxes { profile, settings }
// enum LogBoxes { crash, history }

// // 💡 믹스인(with) 대신 구현(implements) 구조로 바꿉니다.
// enum MyCollections implements AppCollection<Enum> {
//   user(UserBoxes.values),
//   logs(LogBoxes.values);

//   // 추상 클래스의 생성자와 연결시켜 주기 위한 필수 '최소' 코드 (단 두 줄)
//   @override
//   final Iterable<Enum> boxTypes;
//   const MyCollections(this.boxTypes);
// }
/// ```
abstract class AppCollection<T extends Enum> {
  // 1. enum 고유의 name 프로퍼티와 일치하도록 명세만 열어둡니다.
  String get name;

  // 2. 생성자에서 인수로 받을 핵심 멤버 변수
  final Iterable<T> boxTypes;

  // 3. 지저분했던 변환 로직들을 부모 레이어에서 알아서 계산하도록 처리
  Set<String> get boxNames => boxTypes.map((e) => e.name).toSet();

  // 4. 생성자를 통해 자식(enum)으로부터 값을 안전하게 주입받습니다.
  const AppCollection(this.boxTypes);

  Future<BoxCollection> get collection async =>
      await AppDatabase.instance.openCollection(name, boxNames);

  Future<CollectionBox> open(T boxType) async {
    final col = await collection;
    return await AppDatabase.instance.openBox(col, boxType.name);
  }

  Future<void> run(
    Future Function(BoxCollection) action, {
    bool readOnly = false,
  }) async {
    final c = await collection;
    await c.transaction(
      () async => await action(c),
      boxNames: c.boxNames.toList(),
      readOnly: readOnly,
    );
  }
}
