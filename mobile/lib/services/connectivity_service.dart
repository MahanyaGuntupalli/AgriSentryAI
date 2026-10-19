import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Connectivity state (Master Prompt sections 5, 16).
/// online / offline, exposed as a listenable so any screen or the
/// sync manager can react without polling.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final ValueNotifier<bool> isOnline = ValueNotifier(true);
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Starts listening. Safe to call multiple times.
  Future<void> start() async {
    if (_sub != null) return;
    try {
      final results = await Connectivity().checkConnectivity();
      _apply(results);
      _sub = Connectivity()
          .onConnectivityChanged
          .listen(_apply, onError: (_) => isOnline.value = false);
    } catch (_) {
      // Platform without the plugin (e.g. some desktops/tests): assume online
      // so the app still functions; real API calls decide reachability.
      isOnline.value = true;
    }
  }

  void _apply(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    final wasOffline = !isOnline.value;
    isOnline.value = !offline;
    if (wasOffline && !offline) {
      _onlineAgain?.call();
    }
  }

  void Function()? _onlineAgain;

  /// Register a callback fired when the device comes back online
  /// (used by SyncService to auto-retry pending uploads).
  void onOnlineAgain(void Function() cb) => _onlineAgain = cb;

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
