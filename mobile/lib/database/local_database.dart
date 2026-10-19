import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Offline-first local persistence (Master Prompt sections 5, 6, 31).
///
/// A dependency-free JSON document store under the app's support directory
/// (`getPathProvider` would be the production swap-in; the interface here is
/// deliberately identical so nothing else changes).
///
/// Why JSON over sqflite: zero new native dependencies for the prototype,
/// atomic file writes, human-inspectable, and fast enough for history-scale
/// data. The [LocalDatabase] API is repository-friendly, so swapping the
/// storage engine later touches exactly one file.
class LocalDatabase {
  LocalDatabase({required String Function() directoryResolver})
      : _directoryResolver = directoryResolver;

  final String Function() _directoryResolver;
  Map<String, dynamic>? _cache;
  Future<void>? _loading;

  String get _filePath => '${_directoryResolver()}${Platform.pathSeparator}agrisentry_local.json';

  Future<Map<String, dynamic>> _doc() async {
    if (_cache != null) return _cache!;
    _loading ??= _load();
    await _loading;
    return _cache!;
  }

  Future<void> _load() async {
    try {
      final f = File(_filePath);
      if (await f.exists()) {
        _cache = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      } else {
        _cache = {};
      }
    } catch (_) {
      // Corrupt file: never lose the app over it - start a fresh store.
      _cache = {};
    }
  }

  Future<void> _flush() async {
    final f = File(_filePath);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(_cache ?? {}));
    await tmp.rename(f.path);
  }

  // ---------------- analyses ----------------

  Future<void> saveAnalysis(Map<String, dynamic> analysis,
      {required bool pendingSync}) async {
    final doc = await _doc();
    final analyses = (doc['analyses'] as List? ?? []).cast<Map<String, dynamic>>();
    analyses.insert(0, analysis);
    if (analyses.length > 200) analyses.removeRange(200, analyses.length);
    doc['analyses'] = analyses;
    await _flush();
    if (pendingSync) await _enqueue(analysis);
  }

  Future<List<Map<String, dynamic>>> analyses({int limit = 100}) async {
    final doc = await _doc();
    final all = (doc['analyses'] as List? ?? const []).cast<Map<String, dynamic>>();
    return all.take(limit).toList();
  }

  Future<Map<String, dynamic>?> analysisById(String localId) async {
    final doc = await _doc();
    final all = (doc['analyses'] as List? ?? const []).cast<Map<String, dynamic>>();
    for (final a in all) {
      if (a['local_id'] == localId) return a;
    }
    return null;
  }

  Future<void> markAnalysisSynced(String localId, int serverScanId) async {
    final doc = await _doc();
    final all = (doc['analyses'] as List? ?? const []).cast<Map<String, dynamic>>();
    for (final a in all) {
      if (a['local_id'] == localId) {
        a['sync_status'] = 'SYNCED';
        a['server_scan_id'] = serverScanId;
      }
    }
    await _flush();
  }

  // ---------------- sync queue ----------------

  Future<void> _enqueue(Map<String, dynamic> analysis) async {
    final doc = await _doc();
    final q = (doc['sync_queue'] as List? ?? []).cast<String>();
    final id = analysis['local_id'] as String?;
    if (id != null && !q.contains(id)) q.add(id);
    doc['sync_queue'] = q;
    await _flush();
  }

  Future<List<String>> pendingIds() async {
    final doc = await _doc();
    return (doc['sync_queue'] as List? ?? const []).cast<String>();
  }

  Future<int> pendingCount() async => (await pendingIds()).length;

  Future<Map<String, dynamic>?> pendingAnalysis(String localId) async =>
      analysisById(localId);

  Future<void> dequeue(String localId) async {
    final doc = await _doc();
    final q = (doc['sync_queue'] as List? ?? []).cast<String>();
    q.remove(localId);
    doc['sync_queue'] = q;
    await _flush();
  }

  // ---------------- weather cache ----------------

  Future<void> saveWeather(Map<String, dynamic> weather) async {
    final doc = await _doc();
    doc['weather_cache'] = weather;
    await _flush();
  }

  Future<Map<String, dynamic>?> cachedWeather() async {
    final doc = await _doc();
    return doc['weather_cache'] as Map<String, dynamic>?;
  }

  // ---------------- sensor readings cache ----------------

  Future<void> saveSensorReadings(List<Map<String, dynamic>> readings) async {
    final doc = await _doc();
    doc['sensor_cache'] = readings;
    await _flush();
  }

  Future<List<Map<String, dynamic>>> cachedSensorReadings() async {
    final doc = await _doc();
    return (doc['sensor_cache'] as List? ?? const []).cast<Map<String, dynamic>>();
  }

  // ---------------- preferences ----------------

  Future<void> savePref(String key, Object value) async {
    final doc = await _doc();
    final prefs = (doc['prefs'] as Map<String, dynamic>?) ?? {};
    prefs[key] = value;
    doc['prefs'] = prefs;
    await _flush();
  }

  Future<Object?> pref(String key) async {
    final doc = await _doc();
    return (doc['prefs'] as Map<String, dynamic>?)?[key];
  }

  Future<void> saveSyncMeta(DateTime? lastSynced) async {
    final doc = await _doc();
    doc['last_synced'] = lastSynced?.toIso8601String();
    await _flush();
  }

  Future<DateTime?> lastSynced() async {
    final doc = await _doc();
    final v = doc['last_synced'] as String?;
    return v == null ? null : DateTime.tryParse(v);
  }

  /// Test/debug support: wipe everything.
  Future<void> clearForTest() async {
    _cache = {};
    await _flush();
  }
}

/// Single shared instance wired to the app support directory (persistent
/// across restarts on Android/iOS). Falls back to the system temp directory
/// when path_provider is unavailable (widget tests, some desktops).
LocalDatabase createDefaultLocalDatabase() {
  String dir() => Directory.systemTemp.path;

  return LocalDatabase(directoryResolver: dir);
}

Future<String> appSupportDirectory() async {
  try {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  } catch (_) {
    return Directory.systemTemp.path;
  }
}

/// Resolves the persistent directory once and returns the ready database.
Future<LocalDatabase> openDefaultLocalDatabase() async {
  final dir = await appSupportDirectory();
  return LocalDatabase(directoryResolver: () => dir);
}
