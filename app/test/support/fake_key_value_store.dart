import 'package:tamis/src/storage/key_value_store.dart';

class FakeKeyValueStore implements KeyValueStore {
  FakeKeyValueStore([Map<String, String>? initial]) : data = {...?initial};

  final Map<String, String> data;
  int writes = 0;

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> setString(String key, String value) async {
    writes++;
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    data.remove(key);
  }
}
