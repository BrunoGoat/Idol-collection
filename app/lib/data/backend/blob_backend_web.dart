import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

import 'blob_backend.dart';

BlobBackend create(String name, {String? basePath}) => _IdbBackend(name);

/// Guarda todo en IndexedDB, que persiste entre visitas y aguanta imágenes.
class _IdbBackend extends BlobBackend {
  _IdbBackend(this.name);

  final String name;
  static const _store = 'blobs';
  late Database _db;

  @override
  Future<void> open() async {
    _db = await idbFactoryBrowser.open(
      'salon-$name',
      version: 1,
      onUpgradeNeeded: (e) => e.database.createObjectStore(_store),
    );
  }

  ObjectStore _os(String mode) => _db.transaction(_store, mode).objectStore(_store);

  @override
  Future<Uint8List?> read(String key) async {
    final v = await _os(idbModeReadOnly).getObject(key);
    if (v == null) return null;
    if (v is Uint8List) return v;
    if (v is ByteBuffer) return v.asUint8List();
    if (v is List) return Uint8List.fromList(v.cast<int>());
    return null;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final txn = _db.transaction(_store, idbModeReadWrite);
    await txn.objectStore(_store).put(bytes, key);
    await txn.completed;
  }

  @override
  Future<void> delete(String key) async {
    final txn = _db.transaction(_store, idbModeReadWrite);
    await txn.objectStore(_store).delete(key);
    await txn.completed;
  }

  @override
  Future<bool> exists(String key) async => (await _os(idbModeReadOnly).getKey(key)) != null;

  @override
  Future<List<String>> keys(String prefix) async {
    final all = await _os(idbModeReadOnly).getAllKeys();
    return [for (final k in all) if (k is String && k.startsWith(prefix)) k];
  }

  @override
  Future<void> clear() async {
    final txn = _db.transaction(_store, idbModeReadWrite);
    await txn.objectStore(_store).clear();
    await txn.completed;
  }
}
