import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/models.dart';

/// Thin client for the FastAPI backend. Uses the exact contract endpoints.
class ApiService {
  final String base;
  ApiService([this.base = AppConfig.apiBaseUrl]);

  Uri _uri(String path) => Uri.parse('$base$path');

  Map<String, dynamic> _handle(http.Response r) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      j = const {};
    }
    if (r.statusCode >= 400) {
      final e = (j['error'] as Map?) ?? const {};
      throw ApiException('${e['code'] ?? 'HTTP_${r.statusCode}'}',
          '${e['message'] ?? 'Server error'}', r.statusCode);
    }
    return j;
  }

  Future<void> health() async => _handle(
      await http.get(_uri('/api/health')).timeout(AppConfig.apiTimeout));

  Future<EnvironmentalData> latestSensors() async => EnvironmentalData.fromJson(
      _handle(await http
          .get(_uri('/api/sensors/latest'))
          .timeout(AppConfig.apiTimeout)));

  Future<List<EnvironmentalData>> sensorHistory({int limit = 50}) async {
    final j = _handle(await http
        .get(_uri('/api/sensors/history?limit=$limit'))
        .timeout(AppConfig.apiTimeout));
    final list = ((j['readings'] as List?) ?? const [])
        .map((e) => EnvironmentalData.fromJson(e))
        .toList();
    return list.reversed.toList(); // oldest -> newest for charts
  }

  Future<WeatherData> currentWeather() async => WeatherData.fromJson(
      _handle(await http
          .get(_uri('/api/weather/current'))
          .timeout(AppConfig.apiTimeout)));

  Future<List<ScanHistoryItem>> history({int limit = 50}) async {
    final j = _handle(await http
        .get(_uri('/api/history?limit=$limit'))
        .timeout(AppConfig.apiTimeout));
    return ((j['scans'] as List?) ?? const [])
        .map((e) => ScanHistoryItem.fromJson(e))
        .toList();
  }

  Future<Map<String, dynamic>> scanDetail(int id) async => _handle(await http
      .get(_uri('/api/history/$id'))
      .timeout(AppConfig.apiTimeout));

  Future<ImageAnalysisResult> analyze(File image,
      {String crop = 'tomato', String? deviceId}) async {
    final req = http.MultipartRequest('POST', _uri('/api/analyze'))
      ..fields['crop_name'] = crop;
    if (deviceId != null) req.fields['device_id'] = deviceId;
    req.files.add(await http.MultipartFile.fromPath('file', image.path));
    final streamed = await req.send().timeout(const Duration(seconds: 60));
    return ImageAnalysisResult.fromJson(
        _handle(await http.Response.fromStream(streamed)));
  }
}
