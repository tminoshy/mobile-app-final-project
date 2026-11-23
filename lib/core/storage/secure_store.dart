import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models.dart';

class SecureStore {
  final FlutterSecureStorage storage;
  SecureStore([
    this.storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  ]);
  Future<String> deviceId() async {
    var id = await storage.read(key: 'deviceId');
    if (id == null) {
      id = newId();
      await storage.write(key: 'deviceId', value: id);
    }
    return id;
  }

  Future<Json> session() async {
    final raw = await storage.read(key: 'session');
    return raw == null ? {} : asMap(jsonDecode(raw));
  }

  Future<void> saveSession(Json session) =>
      storage.write(key: 'session', value: jsonEncode(session));
  Future<void> clearSession() => storage.delete(key: 'session');
}
