import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

class ImageQualityCheck {
  final int width;
  final int height;
  final int bytes;
  final double brightness;
  final bool tooSmall;
  final bool tooDark;
  final bool tooBright;
  final bool tooBlurry;
  final bool fileEmpty;

  ImageQualityCheck({
    required this.width,
    required this.height,
    required this.bytes,
    required this.brightness,
    required this.tooSmall,
    required this.tooDark,
    required this.tooBright,
    this.tooBlurry = false,
    required this.fileEmpty,
  });

  bool get needsImprovement =>
      fileEmpty || tooSmall || tooDark || tooBright || tooBlurry;

  List<String> get issues {
    final out = <String>[];
    if (fileEmpty) out.add('The photo file is empty or unreadable.');
    if (tooSmall) {
      out.add('Resolution is low ($width×$height). Move closer and recapture.');
    }
    if (tooDark) out.add('The photo looks too dark. Use daylight, not shade.');
    if (tooBright) {
      out.add('The photo looks overexposed. Avoid direct glare.');
    }
    if (tooBlurry) {
      out.add('The photo looks blurry. Hold the phone steady and retake it.');
    }
    return out;
  }

  List<(String, bool, String)> get checklist => [
        ('Resolution', !tooSmall, '$width×$height'),
        ('Lighting', !tooDark && !tooBright, brightnessLabel),
        ('Sharpness', !tooBlurry, tooBlurry ? 'Blurry' : 'OK'),
        ('File', !fileEmpty, '${(bytes / 1024).round()} KB'),
      ];

  String get brightnessLabel {
    if (tooDark) return 'Too dark';
    if (tooBright) return 'Too bright';
    return 'OK';
  }
}

Future<ImageQualityCheck> inspectLeafPhoto(File file) async {
  if (!await file.exists()) {
    return ImageQualityCheck(
      width: 0,
      height: 0,
      bytes: 0,
      brightness: 0,
      tooSmall: true,
      tooDark: true,
      tooBright: false,
      fileEmpty: true,
    );
  }
  final bytes = await file.length();
  if (bytes == 0) {
    return ImageQualityCheck(
      width: 0,
      height: 0,
      bytes: 0,
      brightness: 0,
      tooSmall: true,
      tooDark: true,
      tooBright: false,
      fileEmpty: true,
    );
  }
  final data = await file.readAsBytes();
  // Performance: read the intrinsic size without a full-resolution decode,
  // and decode a small 160px thumbnail for brightness/blur analysis.
  final buffer = await ui.ImmutableBuffer.fromUint8List(data);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final w = descriptor.width;
  final h = descriptor.height;
  descriptor.dispose();
  buffer.dispose();
  final thumbCodec = await ui.instantiateImageCodec(data, targetWidth: 160);
  final frame = await thumbCodec.getNextFrame();
  final image = frame.image;
  final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  final brightness = _meanBrightness(bd);
  final blurScore = _laplacianVariance(bd, image.width, image.height);
  // Threshold tuned for the 160px-wide grayscale preview (mirrors the
  // backend's full-resolution Laplacian variance gate).
  return ImageQualityCheck(
    width: w,
    height: h,
    bytes: bytes,
    brightness: brightness,
    tooSmall: w < 400 || h < 400,
    tooDark: brightness < 0.18,
    tooBright: brightness > 0.88,
    tooBlurry: blurScore < 45,
    fileEmpty: false,
  );
}

/// Variance of the 4-neighbour Laplacian over the grayscale preview.
/// Sharp photos have strong edge responses (high variance); blurred ones
/// are flat (low variance).
double _laplacianVariance(ByteData? bd, int w, int h) {
  if (bd == null || bd.lengthInBytes < 4) return 0;
  final bytes = bd.buffer.asUint8List();
  if (w < 3 || h < 3) return 0;
  double sum = 0, sumSq = 0;
  var n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = (y * w + x) * 4;
      final c = _lum(bytes[i], bytes[i + 1], bytes[i + 2]);
      final l = _lum(bytes[i - 4], bytes[i - 3], bytes[i - 2]);
      final r = _lum(bytes[i + 4], bytes[i + 5], bytes[i + 6]);
      final t = _lum(bytes[(y - 1) * w * 4 + x * 4],
          bytes[(y - 1) * w * 4 + x * 4 + 1],
          bytes[(y - 1) * w * 4 + x * 4 + 2]);
      final b = _lum(bytes[(y + 1) * w * 4 + x * 4],
          bytes[(y + 1) * w * 4 + x * 4 + 1],
          bytes[(y + 1) * w * 4 + x * 4 + 2]);
      final lap = -4 * c + l + r + t + b;
      sum += lap;
      sumSq += lap * lap;
      n++;
    }
  }
  if (n == 0) return 0;
  final mean = sum / n;
  return sumSq / n - mean * mean;
}

double _lum(int r, int g, int b) => 0.299 * r + 0.587 * g + 0.114 * b;

double _meanBrightness(ByteData? bd) {
  if (bd == null || bd.lengthInBytes < 4) return 0.5;
  final bytes = bd.buffer.asUint8List();
  var sum = 0.0;
  var n = 0;
  for (var i = 0; i < bytes.length; i += 16) {
    final r = bytes[i];
    final g = bytes[i + 1];
    final b = bytes[i + 2];
    sum += (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
    n++;
  }
  return n == 0 ? 0.5 : sum / n;
}
