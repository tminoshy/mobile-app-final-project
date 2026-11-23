import 'package:dio/dio.dart';

import '../models.dart';
import '../storage/secure_store.dart';
import 'api_error.dart';

class DioApi implements Api {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );
  final SecureStore secure;
  final Dio dio;
  Json credentials = {};
  String deviceId = '';
  Future<void>? _refreshing;
  int _credentialGeneration = 0;
  Future<void> _credentialTail = Future.value();
  void Function()? onExpired;
  DioApi(this.secure, {Dio? client})
    : dio =
          client ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              sendTimeout: const Duration(seconds: 25),
            ),
          );
  Future<void> initialize() async {
    deviceId = await secure.deviceId();
    credentials = await secure.session();
  }

  Future<void> setCredentials(Json value) {
    final generation = ++_credentialGeneration;
    final operation = _credentialTail.then((_) async {
      if (generation != _credentialGeneration) return;
      await secure.saveSession(value);
      if (generation == _credentialGeneration) credentials = value;
    });
    _credentialTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> clear() {
    _credentialGeneration++;
    credentials = {};
    final operation = _credentialTail.then((_) => secure.clearSession());
    _credentialTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  bool get authenticated => credentials['accessToken'] != null;
  @override
  Future<dynamic> call(
    String method,
    String path, {
    Json? data,
    Json? query,
    String? idempotencyKey,
  }) async {
    Future<dynamic> send() async => (await dio.request<dynamic>(
      path,
      data: data,
      queryParameters: query,
      options: Options(
        method: method,
        headers: {
          'X-Device-Id': deviceId,
          if (authenticated)
            'Authorization': 'Bearer ${credentials['accessToken']}',
          'Idempotency-Key': ?idempotencyKey,
        },
      ),
    )).data;
    try {
      return await send();
    } on DioException catch (e) {
      final authPath = path.startsWith('/auth/');
      if (e.response?.statusCode == 401 &&
          !authPath &&
          credentials['refreshToken'] != null) {
        await (_refreshing ??= _refresh().whenComplete(() {
          _refreshing = null;
        }));
        try {
          return await send();
        } on DioException catch (retry) {
          throw _map(retry);
        }
      }
      throw _map(e);
    }
  }

  Future<void> _refresh() async {
    final generation = _credentialGeneration;
    try {
      final response = asMap(
        (await dio.post<dynamic>(
          '/auth/refresh',
          data: {'refreshToken': credentials['refreshToken']},
          options: Options(headers: {'X-Device-Id': deviceId}),
        )).data,
      );
      if (generation != _credentialGeneration) {
        throw const ApiError(
          'SESSION_CHANGED',
          'This account session has ended.',
        );
      }
      await setCredentials({...credentials, ...response});
    } on DioException catch (e) {
      final error = _map(e);
      if (e.response?.statusCode == 401 ||
          error.code == 'INVALID_REFRESH_TOKEN') {
        onExpired?.call();
      }
      throw error;
    }
  }

  ApiError _map(DioException e) => e.response == null
      ? const ApiError('NETWORK_ERROR', 'Cannot reach the server.')
      : ApiError.fromJson(
          asMap(e.response?.data),
          httpStatus: e.response?.statusCode,
        );
}
