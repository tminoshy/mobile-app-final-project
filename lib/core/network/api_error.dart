import '../models.dart';

class ApiError implements Exception {
  final String code, message;
  final Json current;
  final List<Json> details;
  final int? httpStatus;
  const ApiError(
    this.code,
    this.message, {
    this.current = const {},
    this.details = const [],
    this.httpStatus,
  });
  factory ApiError.fromJson(Json j, {int? httpStatus}) {
    final e = asMap(j['error'] ?? j);
    return ApiError(
      e['code']?.toString() ?? 'SERVER_ERROR',
      e['message']?.toString() ?? 'Something went wrong. Please retry.',
      current: asMap(e['current']),
      details: asList(e['details']),
      httpStatus: httpStatus,
    );
  }
  bool get offline => code == 'NETWORK_ERROR';
  String get friendly => switch (code) {
    'NETWORK_ERROR' =>
      'Cannot reach the server. Your personal records are saved on this phone.',
    'VERSION_CONFLICT' =>
      'This was changed elsewhere. Refresh and review the latest version.',
    'INVALID_REFRESH_TOKEN' || 'TOKEN_EXPIRED' || 'UNAUTHORIZED' =>
      'Your session expired. Sign in again to sync your records.',
    'GROUP_READ_ONLY' => 'This group is read-only.',
    'SHARED_ENTRY_READ_ONLY' => 'Change this expense from its group.',
    'INVITATION_EXPIRED' || 'INVITATION_REVOKED' =>
      'This invitation is no longer available. Ask for a new code.',
    'FORBIDDEN' ||
    'GROUP_NOT_FOUND' ||
    'NOT_FOUND' => 'This record is unavailable or you no longer have access.',
    _ => message,
  };
  @override
  String toString() => friendly;
}

abstract interface class Api {
  Future<dynamic> call(
    String method,
    String path, {
    Json? data,
    Json? query,
    String? idempotencyKey,
  });
}
