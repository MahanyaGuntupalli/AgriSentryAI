import '../database/local_database.dart';
import 'analysis_orchestrator.dart';
import 'api_service.dart';
import 'connectivity_service.dart';
import 'sync_service.dart';

/// Simple service locator initialized once in main() before runApp.
///
/// Keeps construction out of widgets (Master Prompt section 36) and lets
/// tests substitute fake databases if needed.
class AppServices {
  AppServices._wired(this.db, this.sync, this.analysis);

  final LocalDatabase db;
  final SyncService sync;
  final AnalysisOrchestrator analysis;

  static AppServices? _instance;

  static AppServices get instance => _instance!;

  static bool get isReady => _instance != null;

  /// Called once from main() after language load.
  static Future<AppServices> initialize() async {
    if (_instance != null) return _instance!;
    final db = await openDefaultLocalDatabase();
    final sync = SyncService(db, ApiService());
    final analysis = AnalysisOrchestrator(db: db, sync: sync);
    final services = AppServices._wired(db, sync, analysis);
    _instance = services;
    await ConnectivityService.instance.start();
    await sync.init();
    return services;
  }
}
