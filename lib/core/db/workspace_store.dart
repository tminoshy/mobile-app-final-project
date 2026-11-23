import '../models.dart';

class WorkspaceData {
  Map<String, Json> categories = {}, buckets = {}, entries = {};
  List<Json> outbox = [], deletionMarkers = [];
  Map<String, Json> groupCache = {}, notificationCache = {};
  Set<String> alerts = {};
  Json settings = {
    'epoch': newId(),
    'cursor': '0',
    'welcomeSeen': false,
    'bucketAlerts': true,
    'groupAlerts': true,
  };
  int sequence = 0;
  Map<String, Json> records(String type) => switch (type) {
    'category' => categories,
    'bucket' => buckets,
    'entry' => entries,
    _ => throw ArgumentError(type),
  };
  Json toJson() => {
    'categories': categories,
    'buckets': buckets,
    'entries': entries,
    'outbox': outbox,
    'deletionMarkers': deletionMarkers,
    'groupCache': groupCache,
    'notificationCache': notificationCache,
    'alerts': alerts.toList(),
    'settings': settings,
    'sequence': sequence,
  };
  factory WorkspaceData.fromJson(Json j) {
    Map<String, Json> records(Object? value) =>
        asMap(value).map((k, v) => MapEntry(k, asMap(v)));
    return WorkspaceData()
      ..categories = records(j['categories'])
      ..buckets = records(j['buckets'])
      ..entries = records(j['entries'])
      ..outbox = asList(j['outbox'])
      ..deletionMarkers = asList(j['deletionMarkers'])
      ..groupCache = records(j['groupCache'])
      ..notificationCache = records(j['notificationCache'])
      ..alerts = Set<String>.from(j['alerts'] ?? [])
      ..settings = asMap(j['settings'])
      ..sequence = (j['sequence'] ?? 0) as int;
  }
  WorkspaceData();
  WorkspaceData copy() => WorkspaceData.fromJson(cloneJson(toJson()));
}

abstract interface class WorkspaceStore {
  Future<WorkspaceData> load();
  Future<void> save(WorkspaceData data);
  Future<void> close();
}

class MemoryWorkspaceStore implements WorkspaceStore {
  WorkspaceData value = WorkspaceData();
  @override
  Future<WorkspaceData> load() async => value.copy();
  @override
  Future<void> save(WorkspaceData data) async {
    value = data.copy();
  }

  @override
  Future<void> close() async {}
}
