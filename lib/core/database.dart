import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mqtt5_client_manually_ack/core/security.dart';

extension SafeBoxCollection on BoxCollection {
  /// 정의된 CollectionBox 에 접근할 수 있습니다.
  Future<CollectionBox<V>> openSafeBox<V>(AppCollection col, String boxName) {
    if (!col.boxes.contains(boxName)) throw Exception("$boxName에 접근할 수 없습니다.");
    return openBox<V>(boxName);
  }
}

enum AppCollection {
  configs(boxes: {'settings', 'logs', 'user'}),
  chats(boxes: {'room', 'room_idx', 'msg'});

  final Set<String> boxes;
  const AppCollection({required this.boxes});

  Future<T> execute<T>(
    FutureOr<T> Function(BoxCollection collection) action, {
    Function()? onComplete,
    bool readOnly = false,
  }) => AppDatabase.instance.execute(
    this,
    action,
    onComplete: onComplete,
    readOnly: readOnly,
  );
}

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  final Map<AppCollection, BoxCollection> _caches = {};
  Completer<void>? _initCompleter;

  Future<void> init({retryCount = 0}) async {
    if (_initCompleter != null && _initCompleter!.isCompleted) return;
    _initCompleter ??= Completer();
    try {
      await Hive.initFlutter();
      await getCollection(AppCollection.configs);
      if (!_initCompleter!.isCompleted) _initCompleter!.complete();
    } catch (e) {
      _initCompleter = null;
      if (retryCount < 3) {
        await Future.delayed(Duration(seconds: 1));
        return init(retryCount: retryCount + 1);
      } else {
        throw Exception("데이터베이스 초기화에 실패하였습니다.");
      }
    }
  }

  Future<BoxCollection> getCollection(AppCollection collection) async {
    if (_caches.containsKey(collection)) return _caches[collection]!;
    if (collection != AppCollection.configs) await _initCompleter?.future;
    final key = await FSS.instance.getEncryptionKey;
    final boxCollection = await BoxCollection.open(
      collection.name,
      collection.boxes,
      path: './',
      key: HiveAesCipher(key),
    );
    _caches[collection] = boxCollection;
    return boxCollection;
  }

  Future<T> execute<T>(
    AppCollection appCollection,
    FutureOr<T> Function(BoxCollection collection) action, {
    Function()? onComplete,
    bool readOnly = false,
  }) async {
    final collection = await getCollection(appCollection);
    late T result;
    await collection.transaction(
      () async {
        result = await action(collection);
      },
      boxNames: appCollection.boxes.toList(),
      readOnly: readOnly,
    );
    onComplete?.call();
    return result;
  }
}
