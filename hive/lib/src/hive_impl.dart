import 'dart:collection';

import 'package:hive/hive.dart';
import 'package:hive/src/adapters/big_int_adapter.dart';
import 'package:hive/src/adapters/date_time_adapter.dart';
import 'package:hive/src/box/box_options.dart';
import 'package:hive/src/box/default_compaction_strategy.dart';
import 'package:hive/src/crypto_helper.dart';
import 'package:hive/src/registry/type_registry_impl.dart';

import 'box/box_impl.dart';

class HiveImpl extends TypeRegistryImpl implements HiveInterface {
  final _boxes = HashMap<String, Box>();

  String _homePath;

  HiveImpl() {
    registerInternal(DateTimeAdapter(), 16);
    registerInternal(BigIntAdapter(), 17);
  }

  @override
  String get path {
    if (_homePath == null) {
      throw HiveError('Hive not initialized. Call Hive.init() first.');
    }

    return _homePath;
  }

  @override
  void init(String path) {
    _homePath = path;

    _boxes.clear();
  }

  @override
  Future<Box> box(
    String name, {
    List<int> encryptionKey,
    bool lazy = false,
    CompactionStrategy compactionStrategy,
  }) async {
    var existingBox = _boxes[name.toLowerCase()];
    if (existingBox != null) return existingBox;

    var options = BoxOptions(
      encryptionKey: encryptionKey,
      lazy: lazy,
      compactionStrategy: defaultCompactionStrategy,
    );

    var box = await openBox(this, name.toLowerCase(), options);
    _boxes[name.toLowerCase()] = box;

    return box;
  }

  @override
  bool isBoxOpen(String name) {
    return _boxes.containsKey(name.toLowerCase());
  }

  @override
  Box operator [](String name) {
    return _boxes[name.toLowerCase()];
  }

  @override
  Future close() {
    var closeFutures = _boxes.values.map((box) {
      return box.close();
    });

    return Future.wait(closeFutures);
  }

  void unregisterBox(String name) {
    _boxes.remove(name.toLowerCase());
  }

  @override
  Future deleteFromDisk() {
    var deleteFutures = _boxes.values.toList().map((box) {
      return box.deleteFromDisk();
    });

    return Future.wait(deleteFutures);
  }

  @override
  List<int> generateSecureKey() {
    var secureRandom = CryptoHelper.createSecureRandom();
    return secureRandom.nextBytes(32);
  }
}
