import 'dart:convert';

import '../../core/models.dart';
import '../../core/network/api_error.dart';
import '../entries/workspace.dart';

class GroupRepository {
  final Api api;
  final Workspace workspace;
  bool lastReadWasCached = false;
  GroupRepository(this.api, this.workspace);
  Future<dynamic> read(String path, {Json? query}) async {
    final epoch = workspace.data.settings['epoch'];
    final cacheKey = '$path?${query ?? {}}';
    try {
      dynamic result = await api.call('GET', path, query: query);
      if (asMap(result)['hasMore'] == true) {
        final collected = items(result);
        final seen = <String>{};
        var page = asMap(result);
        while (page['hasMore'] == true) {
          final cursor = page['nextCursor']?.toString();
          if (cursor == null || !seen.add(cursor)) {
            throw const ApiError(
              'INVALID_RESPONSE',
              'The list cursor did not advance. Please refresh.',
            );
          }
          page = asMap(
            await api.call('GET', path, query: {...?query, 'cursor': cursor}),
          );
          collected.addAll(items(page));
        }
        result = {
          ...asMap(result),
          'items': collected,
          'hasMore': false,
          'nextCursor': page['nextCursor'],
        };
      }
      await workspace.transaction((d) {
        if (d.settings['epoch'] != epoch) {
          throw const ApiError(
            'SESSION_CHANGED',
            'This account session has ended.',
          );
        }
        d.groupCache[cacheKey] = {
          'value': result,
          'cachedAt': DateTime.now().toUtc().toIso8601String(),
        };
      });
      lastReadWasCached = false;
      return result;
    } on ApiError catch (e) {
      if (workspace.data.settings['epoch'] != epoch) rethrow;
      if (!e.offline || !workspace.data.groupCache.containsKey(cacheKey)) {
        rethrow;
      }
      lastReadWasCached = true;
      return workspace.data.groupCache[cacheKey]!['value'];
    }
  }

  Future<dynamic> write(
    String method,
    String path, {
    Json? data,
    String? key,
  }) => api.call(method, path, data: data, idempotencyKey: key);

  /// Persist the exact request before sending. An ambiguous timeout can only
  /// retry that request, so changing a form cannot accidentally double-charge.
  Future<dynamic> submit(String path, Json data) async {
    final pending = asMap(workspace.data.settings['pendingWrites']);
    final existing = asMap(pending[path]);
    if (existing.isNotEmpty &&
        jsonEncode(existing['data']) != jsonEncode(data)) {
      throw const ApiError(
        'PENDING_WRITE',
        'A previous save is awaiting confirmation. Retry it from Account before submitting another change.',
      );
    }
    final request = existing.isNotEmpty
        ? existing
        : {'key': newId(), 'path': path, 'data': data};
    await workspace.transaction((d) {
      final writes = asMap(d.settings['pendingWrites']);
      writes[path] = request;
      d.settings['pendingWrites'] = writes;
    });
    return retrySubmission(path);
  }

  Future<dynamic> retrySubmission(String path) async {
    final request = asMap(
      asMap(workspace.data.settings['pendingWrites'])[path],
    );
    if (request.isEmpty) {
      throw const ApiError(
        'NOT_FOUND',
        'This pending save has already been resolved.',
      );
    }
    dynamic result;
    try {
      result = await api.call(
        'POST',
        path,
        data: asMap(request['data']),
        idempotencyKey: request['key'] as String,
      );
    } on ApiError catch (e) {
      if (e.httpStatus != null && e.httpStatus! >= 400 && e.httpStatus! < 500) {
        await workspace.transaction((d) {
          final writes = asMap(d.settings['pendingWrites']);
          writes.remove(path);
          d.settings['pendingWrites'] = writes;
        });
      }
      rethrow;
    }
    await workspace.transaction((d) {
      final writes = asMap(d.settings['pendingWrites']);
      writes.remove(path);
      d.settings['pendingWrites'] = writes;
    });
    return result;
  }

  Future<List<Json>> groups() async => items(await read('/groups'));
  Future<Json> group(String id) async => asMap(await read('/groups/$id'));
  Future<Json> balances(String id) async =>
      asMap(await read('/groups/$id/balances'));
  Future<Json> expense(String gid, String eid) async =>
      asMap(await read('/groups/$gid/expenses/$eid'));
  Future<Json> repayment(String gid, String rid) async =>
      asMap(await read('/groups/$gid/repayments/$rid'));
  Future<Json> correction(String gid, String cid) async =>
      asMap(await read('/groups/$gid/corrections/$cid'));
  String memberId(Json m) => (m['userId'] ?? m['id']).toString();
  String memberName(Json m) =>
      (m['displayName'] ??
              m['name'] ??
              asMap(m['user'])['displayName'] ??
              'Member')
          .toString();
}
