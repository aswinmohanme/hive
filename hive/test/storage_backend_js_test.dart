@TestOn('browser')

import 'dart:async' show Future;
import 'dart:html';
import 'dart:indexed_db';
import 'dart:typed_data';

import 'package:hive/src/backend/storage_backend_js.dart';
import 'package:hive/src/binary/frame.dart';
import 'package:hive/src/box/box_impl.dart';
import 'package:hive/src/crypto_helper.dart';
import 'package:test/test.dart';

Future<Database> openDb() async {
  return await window.indexedDB.open('testBox', version: 1,
      onUpgradeNeeded: (e) {
    var db = e.target.result as Database;
    if (!db.objectStoreNames.contains('box')) {
      db.createObjectStore('box');
    }
  });
}

ObjectStore getStore(Database db) {
  return db.transaction('box', 'readwrite').objectStore('box');
}

Future<Database> getDbWith(Map<String, dynamic> content) async {
  var db = await openDb();
  var store = getStore(db);
  await store.clear();
  content.forEach((k, v) => store.put(v, k));
  return db;
}

void main() {
  group('StorageBackendJs', () {
    test('.path', () {
      expect(StorageBackendJs(null, null).path, null);
    });

    group('.encodeValue()', () {
      test('primitive', () {
        var backend = StorageBackendJs(null, null);
        expect(backend.encodeValue(11), 11);
        expect(backend.encodeValue(17.25), 17.25);
        expect(backend.encodeValue(true), true);
        expect(backend.encodeValue('hello'), 'hello');
        expect(backend.encodeValue([11, 12, 13]), [11, 12, 13]);
        expect(backend.encodeValue([17.25, 17.26]), [17.25, 17.26]);
      });

      test('primitive crypto', () {
        var crypto = CryptoHelper(Uint8List.fromList(List.filled(32, 1)));
        var backend = StorageBackendJs(null, crypto);
        var bytes = Uint8List.view(backend.encodeValue(1) as ByteBuffer);
        var frame = Frame.bodyFromBytes(bytes, null, crypto);
        expect(frame.value, 1);
      });

      test('non primitive', () {
        var backend = StorageBackendJs(null, null);
        var map = {
          'key': Uint8List.fromList([1, 2, 3]),
          'otherKey': null
        };
        var bytes = Uint8List.view(backend.encodeValue(map) as ByteBuffer);
        var frame = Frame.bodyFromBytes(bytes, null, null);
        expect(frame.value, map);
      });
    });

    group('.decodeValue()', () {
      test('primitive', () {
        var backend = StorageBackendJs(null, null);
        expect(backend.decodeValue(11), 11);
        expect(backend.decodeValue(17.25), 17.25);
        expect(backend.decodeValue(true), true);
        expect(backend.decodeValue('hello'), 'hello');
        expect(backend.decodeValue([11, 12, 13]), [11, 12, 13]);
        expect(backend.decodeValue([17.25, 17.26]), [17.25, 17.26]);
      });

      test('primitive crypto', () {
        var crypto = CryptoHelper(Uint8List.fromList(List.filled(32, 1)));
        var backend = StorageBackendJs(null, crypto);
        var bytes = const Frame('', 1).toBytes(false, null, crypto);
        var value = backend.decodeValue(bytes.buffer);
        expect(value, 1);
      });
    });

    test('.getKeys()', () async {
      var db = await getDbWith({'key1': 1, 'key2': 2, 'key3': 3});
      var backend = StorageBackendJs(db, null);

      expect(await backend.getKeys(), ['key1', 'key2', 'key3']);
    });

    test('.getValues()', () async {
      var db = await getDbWith({'key1': 1, 'key2': 2, 'key3': 3});
      var backend = StorageBackendJs(db, null);

      expect(await backend.getValues(), [1, 2, 3]);
    });

    group('.initialize()', () {
      test('not lazy', () async {
        var db = await getDbWith({'key1': 1, 'key2': 2, 'key3': 3});
        var backend = StorageBackendJs(db, null);

        var entries = <String, BoxEntry>{};
        expect(await backend.initialize(entries, false), 0);
        expect(entries, {
          'key1': const BoxEntry(1, null, null),
          'key2': const BoxEntry(2, null, null),
          'key3': const BoxEntry(3, null, null)
        });
      });

      test('lazy', () async {
        var db = await getDbWith({'key1': 1, 'key2': 2, 'key3': 3});
        var backend = StorageBackendJs(db, null);

        var entries = <String, BoxEntry>{};
        expect(await backend.initialize(entries, true), 0);
        expect(entries, {
          'key1': const BoxEntry(null, null, null),
          'key2': const BoxEntry(null, null, null),
          'key3': const BoxEntry(null, null, null)
        });
      });
    });

    test('.readValue()', () async {
      var db = await getDbWith({'key1': 1, 'key2': 2, 'key3': 3});
      var backend = StorageBackendJs(db, null);

      expect(await backend.readValue('key2', null, null), 2);
    });

    test('.readAll()', () async {
      var db = await getDbWith({'key1': 1, 'key2': 2, 'key3': 3});
      var backend = StorageBackendJs(db, null);

      expect(await backend.readAll(['key1', 'key2', 'key3']),
          {'key1': 1, 'key2': 2, 'key3': 3});
    });

    test('.writeFrame()', () async {
      var db = await getDbWith({});
      var backend = StorageBackendJs(db, null);

      var entry = await backend.writeFrame(const Frame('key1', 123), false);
      expect(entry, const BoxEntry(123, null, null));
      expect(await backend.getKeys(), ['key1']);

      entry = await backend.writeFrame(const Frame('key2', 456), true);
      expect(entry, const BoxEntry(null, null, null));
      expect(await backend.getKeys(), ['key1', 'key2']);

      entry = await backend.writeFrame(const Frame('key1', null), false);
      expect(entry, null);
      expect(await backend.getKeys(), ['key2']);
    });

    test('.writeFrames()', () async {
      var db = await getDbWith({});
      var backend = StorageBackendJs(db, null);

      var entries = await backend.writeFrames([
        const Frame('key1', 123),
        const Frame('key2', 456),
      ], false);
      expect(entries, [
        const BoxEntry(123, null, null),
        const BoxEntry(456, null, null),
      ]);
      expect(await backend.getKeys(), ['key1', 'key2']);

      entries = await backend.writeFrames([
        const Frame('key1', null),
        const Frame('key3', 789),
      ], true);
      expect(entries, [null, const BoxEntry(null, null, null)]);
      expect(await backend.getKeys(), ['key2', 'key3']);
    });

    test('.compact()', () async {
      var db = await getDbWith({});
      var backend = StorageBackendJs(db, null);

      var entries = {
        'key1': const BoxEntry(null, null, null),
        'key2': const BoxEntry(null, null, null)
      };
      expect(await backend.compact(entries), entries);
    });

    test('.clear()', () async {
      var db = await getDbWith({'key1': 1, 'key2': 2, 'key3': 3});
      var backend = StorageBackendJs(db, null);
      await backend.clear();
      expect(await backend.getKeys(), []);
    });

    test('.close()', () async {
      var db = await getDbWith({'key1': 1, 'key2': 2, 'key3': 3});
      var backend = StorageBackendJs(db, null);
      await backend.close();

      expect(() async => await backend.getKeys(), throwsA(anything));
    });
  });
}
