import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ai/crop_disease_knowledge.dart';
import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../utils/app_routes.dart';
import '../utils/image_quality.dart';
import '../widgets/common.dart';
import 'analysis_loading_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _image;
  ImageQualityCheck? _quality;
  bool _picking = false;
  bool _checking = false;
  CropType? _crop;

  /// True only when the farmer explicitly picked a crop (or picked one in a
  /// previous session). No silent tomato assumption (audit section 3).
  bool _cropSelected = false;

  @override
  void initState() {
    super.initState();
    LanguageService.instance.language.addListener(_languageChanged);
    _loadCropPreference();
    _restoreLostImage();
  }

  Future<void> _loadCropPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final saved = prefs.getString('selected_crop');
    setState(() {
      _cropSelected = saved != null;
      _crop = CropType.tryParse(saved);
    });
  }

  Future<void> _selectCrop(CropType crop) async {
    setState(() {
      _crop = crop;
      _cropSelected = true;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_crop', crop.id);
  }

  Future<void> _restoreLostImage() async {
    try {
      final response = await _picker.retrieveLostData();
      if (!mounted || response.isEmpty) return;
      if (response.file != null) {
        await _usePickedFile(response.file!);
      } else if (response.exception != null) {
        _showPickerError(response.exception!);
      }
    } on PlatformException catch (e) {
      _showPickerError(e);
    } on MissingPluginException {
      _showMessage(
          'Camera or gallery is unavailable on this platform. Please choose an image from a supported device.');
    } on FileSystemException {
      _showMessage(
          'The selected image could not be read. Please choose another image.');
    }
  }

  void _languageChanged() => setState(() {});

  @override
  void dispose() {
    LanguageService.instance.language.removeListener(_languageChanged);
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _picking = true);
    try {
      final picked = await _picker.pickImage(
          source: source, maxWidth: 1600, imageQuality: 90);
      if (picked != null) await _usePickedFile(picked);
    } on PlatformException catch (e) {
      _showPickerError(e);
    } on MissingPluginException {
      _showMessage(
          'Camera or gallery is unavailable on this platform. Please choose an image from a supported device.');
    } on FileSystemException {
      _showMessage(
          'The selected image could not be read. Please choose another image.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _usePickedFile(XFile picked) async {
    final file = File(picked.path);
    if (!await file.exists() || await file.length() == 0) {
      _showMessage(
          'The selected image is empty or unavailable. Please choose another image.');
      return;
    }
    final extension = picked.path.toLowerCase().split('.').last;
    if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
      _showMessage(
          'Please choose a JPG, PNG, or WebP crop image.');
      return;
    }
    if (mounted) {
      setState(() {
        _image = file;
        _quality = null;
        _checking = true;
      });
    }
    final quality = await inspectLeafPhoto(file);
    if (mounted) {
      setState(() {
        _quality = quality;
        _checking = false;
      });
    }
  }

  void _showPickerError(PlatformException error) {
    final code = error.code.toLowerCase();
    final message = code.contains('permission') || code.contains('denied')
        ? 'Camera permission is required to take a crop photo. You can enable it in Settings or choose an existing image.'
        : 'Camera is not available on this device. You can choose a crop image from your gallery instead.';
    _showMessage(message);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(tr(message)),
          action: SnackBarAction(
              label: tr('Gallery'),
              onPressed: () => _pick(ImageSource.gallery))));
  }

  Future<void> _startAnalysis() async {
    if (!_cropSelected) {
      _showMessage('Select your crop above so the AI uses the right knowledge.');
      return;
    }
    final image = _image;
    if (image == null || !await image.exists() || await image.length() == 0) {
      _showMessage(
          'The image is no longer available. Please capture or choose it again.');
      return;
    }
    if (!mounted) return;
    final crop = _crop;
    if (crop == null) {
      _showMessage('Select your crop above so the AI uses the right knowledge.');
      return;
    }
    Navigator.push(
        context,
        fadeSlideTo(AnalysisLoadingScreen(
            image: image, crop: crop)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(tr('Scan Crop')),
            actions: [
              SpeakButton(
                  text: () => tr(
                      'Take a clear leaf photo in daylight, then analyze the leaf.')),
              const LanguageToggleButton(),
            ]),
        body: ListView(padding: Spacing.page, children: [
          _CropSelector(
              selected: _crop,
              onSelect: _selectCrop,
              showHint: !_cropSelected),
          const SizedBox(height: Spacing.sm),
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                  color: AppColors.forest.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(Spacing.radius)),
              child: _image == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          const Icon(Icons.eco_outlined,
                              size: 64, color: AppColors.leaf),
                          const SizedBox(height: 10),
                          Text(tr('No leaf photo yet'),
                              style: const TextStyle(color: AppColors.muted)),
                        ])
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(Spacing.radius),
                      child: Stack(fit: StackFit.expand, children: [
                        Image.file(_image!, cacheWidth: 900, fit: BoxFit.cover),
                        CustomPaint(painter: _FrameGuidePainter()),
                      ]),
                    ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: _picking ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(tr('Camera')))),
            const SizedBox(width: Spacing.sm),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: _picking ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(tr('Gallery')))),
          ]),
          if (_checking)
           const Padding(
             padding: EdgeInsets.only(top: Spacing.md),
             child: LinearProgressIndicator(color: AppColors.pine),
           ),
          if (_quality != null && !_checking) ...[
           const SizedBox(height: Spacing.md),
           _QualityCard(check: _quality!),
          ],
          const SizedBox(height: Spacing.md),
          AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(tr('For the best result:'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                    tr('• Use daylight, not direct glare\n'
                        '• Fill the frame with one leaf\n'
                        '• Hold the phone steady\n'
                        '• Include the spotted part of the leaf'),
                    style: const TextStyle(color: AppColors.muted, height: 1.6)),
              ])),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: tr(_image == null
                ? 'TAKE A PHOTO FIRST'
                : _quality?.needsImprovement == true
                    ? 'RETAKE PHOTO'
                    : 'ANALYZE THIS LEAF'),
            icon: Icons.document_scanner_outlined,
            onPressed: _image == null || _quality?.needsImprovement == true
                ? null
                : _startAnalysis,
          ),
        ]),
      );
}

class _CropSelector extends StatelessWidget {
  final CropType? selected;
  final ValueChanged<CropType> onSelect;
  final bool showHint;
  const _CropSelector(
      {required this.selected, required this.onSelect, this.showHint = false});

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(Spacing.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 4, bottom: 6),
            child: Row(children: [
              Text(tr('Your crop'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.forest)),
              if (showHint) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('Select your crop above so the AI uses the right knowledge.'),
                      maxLines: 2,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.amber,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                for (final crop in CropType.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      selected: crop == selected,
                      onSelected: (_) => onSelect(crop),
                      label: Text(tr(crop.displayName)),
                      selectedColor: AppColors.sage,
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w800,
                        color:
                            crop == selected ? AppColors.forest : AppColors.muted,
                      ),
                      side: BorderSide(
                          color: crop == selected
                              ? AppColors.pine
                              : AppColors.line),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
        ]),
      );
}

class _QualityCard extends StatelessWidget {
  final ImageQualityCheck check;
  const _QualityCard({required this.check});

  @override
  Widget build(BuildContext context) {
    final good = !check.needsImprovement;
    return AppCard(
      color: (good ? AppColors.pine : AppColors.amber).withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                good ? Icons.verified_outlined : Icons.info_outline,
                color: good ? AppColors.pine : AppColors.amber,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  tr(good
                      ? 'IMAGE QUALITY LOOKS GOOD'
                      : 'IMAGE QUALITY NEEDS IMPROVEMENT'),
                  style: TextStyle(
                    color: good ? AppColors.pine : const Color(0xFF9A6B1A),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          for (final item in check.checklist)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Icon(
                    item.$2 ? Icons.check_circle_outline : Icons.error_outline,
                    size: 17,
                    color: item.$2 ? AppColors.pine : AppColors.amber,
                  ),
                  const SizedBox(width: 7),
                  Expanded(child: Text(tr(item.$1))),
                  Text(item.$3,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
          if (!good)
            Text(
              tr(check.issues.join(' ')),
              style: const TextStyle(
                  color: AppColors.muted, fontSize: 12.5, height: 1.4),
            ),
        ],
      ),
    );
  }
}

class _FrameGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 34.0, m = 18.0;
    final w = size.width, h = size.height;
    void corner(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x, y), Offset(x + dx * len, y), p);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * len), p);
    }
    corner(m, m, 1, 1);
    corner(w - m, m, -1, 1);
    corner(m, h - m, 1, -1);
    corner(w - m, h - m, -1, -1);
    canvas.drawOval(
        Rect.fromCenter(
            center: size.center(Offset.zero),
            width: w * 0.62,
            height: h * 0.62),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
