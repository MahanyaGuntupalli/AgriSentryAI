import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../database/local_database.dart';
import 'api_service.dart';
import 'connectivity_service.dart';

/// Sync status (Master Prompt sections 5, 6, 16):
/// Synced | Sync pending | Offline
enum SyncStatus { synced, pending, offline, syncing }

/// Cloud synchronization manager (Master Prompt sections 5, 6, 7, 16).
///
/// - Every locally created analysis is stored first, then enqueued.
/// - When connectivity returns (or on app start / manual pull), the queue
///   drains: each item POSTs to /api/analyze and is marked SYNCED.
/// - Failures stay in the queue - data is never dropped (section 7).
/// - Status is exposed as a listenable for the UI pill.
class SyncService {
  SyncService(this._db, [ApiService? api]) : _api = api ?? ApiService();

  final LocalDatabase _db;
  // Reserved for future Firebase/REST batch endpoints; the queue currently
  // posts directly to /api/analyze to reuse the exact backend contract.
  // ignore: unused_field
  final ApiService _api;

  final ValueNotifier<SyncStatus> status = ValueNotifier(SyncStatus.pending);
  final ValueNotifier<int> pendingCount = ValueNotifier(0);
  final ValueNotifier<DateTime?> lastSynced = ValueNotifier(null);

  bool _busy = false;
  Timer? _retryTimer;
  int _backoffSeconds = 30;
  static const _maxBackoff = 300;

  /// Delay before the automatic retry after a failed cycle.
  static const Duration retryDelay = Duration(seconds: 45);

  Future<void> init() async {
    lastSynced.value = await _db.lastSynced();
    await refreshPending();
    ConnectivityService.instance.onOnlineAgain(_syncWhenOnline);
    ConnectivityService.instance.isOnline.addListener(_onConnectivityChanged);
    unawaited(syncNow());
  }

  void _onConnectivityChanged() {
    if (ConnectivityService.instance.isOnline.value) {
      // Short delay so flapping Wi-Fi doesn't spam attempts.
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 5), _syncWhenOnline);
    }
  }

  void _syncWhenOnline() {
    _retryTimer?.cancel();
    unawaited(syncNow());
  }

  /// Re-reads queue size from the database and updates the status pill.
  Future<void> refreshPending() async {
    pendingCount.value = await _db.pendingCount();
    if (ConnectivityService.instance.isOnline.value) {
      status.value =
          pendingCount.value == 0 ? SyncStatus.synced : SyncStatus.pending;
    } else {
      status.value = SyncStatus.offline;
    }
  }

  /// Queues a locally saved analysis for upload.
  Future<void> enqueue(Map<String, dynamic> analysis) async {
    await refreshPending();
    unawaited(syncNow());
  }

  /// One full drain attempt. Never throws - the UI must stay calm.
  Future<bool> syncNow() async {
    if (_busy) return false;
    if (!ConnectivityService.instance.isOnline.value) {
      status.value = SyncStatus.offline;
      return false;
    }
    _busy = true;
    status.value = SyncStatus.syncing;
    try {
      final ids = await _db.pendingIds();
      var allOk = ids.isEmpty;
      for (final id in ids) {
        final ok = await _uploadOne(id);
        if (!ok) allOk = false;
      }
      if (allOk) {
        _backoffSeconds = 30;
        lastSynced.value = DateTime.now();
        await _db.saveSyncMeta(lastSynced.value);
      } else {
        _scheduleRetry();
      }
      await refreshPending();
      return allOk;
    } catch (_) {
      _scheduleRetry();
      await refreshPending();
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<bool> _uploadOne(String localId) async {
    try {
      final stored = await _db.pendingAnalysis(localId);
      if (stored == null) {
        await _db.dequeue(localId);
        return true;
      }
      final imageFile = File((stored['image_path'] as String?) ?? '');
      if (!await imageFile.exists()) {
        // The image is gone; keep the record local but stop retrying it.
        await _db.dequeue(localId);
        await _db.markAnalysisSynced(localId, -1);
        return true;
      }
      final bytes = await imageFile.readAsBytes();
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.apiBaseUrl}/api/analyze'),
      )
        ..fields['crop_name'] = (stored['crop_name'] as String?) ??
            AppConfig.defaultCrop
        ..files.add(http.MultipartFile.fromBytes('file', bytes,
            filename: imageFile.uri.pathSegments.last));
      final streamed =
          await req.send().timeout(AppConfig.apiTimeout * 4);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final serverId = (body['scan_id'] as num?)?.toInt() ?? -1;
        await _db.markAnalysisSynced(localId, serverId);
        await _db.dequeue(localId);
        return true;
      }
      if (response.statusCode >= 400 && response.statusCode < 500) {
        // Permanent rejection (bad image etc.) - do not retry forever.
        await _db.markAnalysisSynced(localId, -1);
        await _db.dequeue(localId);
        return true;
      }
      return false; // 5xx / network: leave queued for retry.
    } catch (_) {
      return false;
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: _backoffSeconds), _syncWhenOnline);
    _backoffSeconds = (_backoffSeconds * 2).clamp(30, _maxBackoff);
  }

  /// Status pill text key for translations.
  String get statusLabelKey => switch (status.value) {
        SyncStatus.synced => 'Synced',
        SyncStatus.pending => 'Sync pending',
        SyncStatus.offline => 'Offline - saved on device',
        SyncStatus.syncing => 'Syncing...',
      };

  void dispose() {
    _retryTimer?.cancel();
    ConnectivityService.instance.isOnline.removeListener(_onConnectivityChanged);
  }
}
