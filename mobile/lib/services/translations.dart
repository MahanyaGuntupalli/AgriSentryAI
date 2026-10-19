/// Telugu and Hindi language support + text-to-speech.
///
/// The farmer-facing text (disease names, risk factors, explanations,
/// recommendations) comes from the backend as fixed rule-based English
/// strings, so Hindi and Telugu are provided as deterministic on-device translations
/// - no network needed, offline-safe (Contract section 27).
///
/// `tr(en)` translates fixed UI strings via an exact dictionary; longer
/// backend strings fall through to sentence-level templates so small backend
/// wording variants (mock vs real) still translate.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

enum AppLanguage { english, telugu, hindi }

/// Holds the selected language and persists it in SharedPreferences.
class LanguageService {
  LanguageService._();
  static final LanguageService instance = LanguageService._();

  static const _prefKey = 'app_language';

  final ValueNotifier<AppLanguage> language =
      ValueNotifier<AppLanguage>(AppLanguage.english);
  SharedPreferences? _prefs;

  AppLanguage get current => language.value;
  bool get isTelugu => current == AppLanguage.telugu;
  bool get isHindi => current == AppLanguage.hindi;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    language.value = switch (_prefs!.getString(_prefKey)) {
      'hi' => AppLanguage.hindi,
      'te' => AppLanguage.telugu,
      _ => AppLanguage.english,
    };
  }

  Future<void> set(AppLanguage lang) async {
    language.value = lang;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_prefKey, switch (lang) {
      AppLanguage.hindi => 'hi',
      AppLanguage.telugu => 'te',
      AppLanguage.english => 'en',
    });
  }

  Future<void> toggle() => set(switch (current) {
        AppLanguage.english => AppLanguage.hindi,
        AppLanguage.hindi => AppLanguage.telugu,
        AppLanguage.telugu => AppLanguage.english,
      });
}

/// Text-to-speech. Uses the platform TTS engine (en-US / hi-IN / te-IN).
class Speaker {
  Speaker._();
  static final Speaker instance = Speaker._();

  final FlutterTts _tts = FlutterTts();
  final ValueNotifier<bool> speaking = ValueNotifier(false);
  bool _handlersSet = false;
  String? _configuredLocale;
  final Set<String> _checkedLocales = <String>{};
  int _generation = 0;
  Completer<void>? _chunkDone;

  void _ensureHandlers() {
    if (_handlersSet) return;
    _tts.setStartHandler(() => speaking.value = true);
    _tts.setCompletionHandler(() {
      final waiter = _chunkDone;
      _chunkDone = null;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
    });
    _tts.setCancelHandler(() {
      final waiter = _chunkDone;
      _chunkDone = null;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
    });
    _tts.setErrorHandler((msg) {
      final waiter = _chunkDone;
      _chunkDone = null;
      if (waiter != null && !waiter.isCompleted) {
        waiter.completeError(StateError('TTS error: $msg'));
      }
    });
    _handlersSet = true;
  }

  Future<void> speak(String text) async {
    _ensureHandlers();
    final session = ++_generation;
    await _cancelCurrentSpeech();
    final locale = switch (LanguageService.instance.current) {
      AppLanguage.english => 'en-US',
      AppLanguage.hindi => 'hi-IN',
      AppLanguage.telugu => 'te-IN',
    };
    try {
      if (_configuredLocale != locale) {
        await _tts.setLanguage(locale);
        _configuredLocale = locale;
      }
      // Voice clarity settings (audit section 9): applied every session so a
      // platform TTS engine restart never silently reverts them.
      // - volume 1.0 = the engine's maximum gain (the physical media volume
      //   is still controlled by the user's volume buttons).
      // - pitch 1.0 = the engine's natural voice; avoids the low robotic
      //   tone some engines fall back to.
      // - rate 0.5 = the Android scale's normal speaking rate (flutter_tts
      //   maps 0..1 across the engine's rate range); 0.45 measured slightly
      //   slow, 0.5 keeps it natural but not dragging.
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.5);
      if (_checkedLocales.add(locale)) {
        final available = await _tts.isLanguageAvailable(locale);
        if (available == false) {
          debugPrint('TTS: no $locale voice installed - using default voice.');
        }
      }
      final chunks = _speechChunks(_cleanSpeechText(text));
      if (chunks.isEmpty) return;
      speaking.value = true;
      for (final chunk in chunks) {
        if (session != _generation) return;
        final done = Completer<void>();
        _chunkDone = done;
        await _tts.speak(chunk);
        await done.future;
      }
    } catch (e) {
      if (session == _generation) {
        debugPrint('TTS unavailable: $e');
      }
    } finally {
      if (session == _generation) speaking.value = false;
    }
  }

  Future<void> stop() async {
    _generation++;
    await _cancelCurrentSpeech();
    speaking.value = false;
  }

  Future<void> _cancelCurrentSpeech() async {
    final waiter = _chunkDone;
    _chunkDone = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    try {
      await _tts.stop();
    } catch (_) {}
  }

  String _cleanSpeechText(String text) {
    return text
        .replaceAll(RegExp(r'[*_#`•🔍🌱🧠🔬🌦️⚠️🩺📅🛡️👀👨‍🌾📌]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s+([:;,.!?])'), r'$1')
        .trim();
  }

  List<String> _speechChunks(String text) {
    if (text.isEmpty) return const [];
    const limit = 2800;
    final sentences = text.split(RegExp(r'(?<=[.!?।！？])\s+'));
    final chunks = <String>[];
    var current = '';
    for (final sentence in sentences) {
      if (sentence.isEmpty) continue;
      if (sentence.length > limit) {
        if (current.isNotEmpty) {
          chunks.add(current);
          current = '';
        }
        final words = sentence.split(' ');
        for (final word in words) {
          if (current.isNotEmpty && current.length + word.length + 1 > limit) {
            chunks.add(current);
            current = '';
          }
          current = current.isEmpty ? word : '$current $word';
        }
        continue;
      }
      if (current.isNotEmpty && current.length + sentence.length + 1 > limit) {
        chunks.add(current);
        current = '';
      }
      current = current.isEmpty ? sentence : '$current $sentence';
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }
}

// ---------------------------------------------------------------------------
// Telugu dictionaries
// ---------------------------------------------------------------------------

/// Disease name -> Telugu (transliterated names farmers recognize).
const Map<String, String> _teDiseases = {
  'Healthy': 'ఆరోగ్యకరం',
  'Early Blight': 'అర్లీ బ్లైట్',
  'Late Blight': 'లేట్ బ్లైట్',
  'Bacterial Spot': 'బ్యాక్టీరియల్ స్పాట్',
  'Leaf Mold': 'లీఫ్ మోల్డ్',
  'Tomato Leaf Mold': 'టమాటా లీఫ్ మోల్డ్',
  'Septoria Leaf Spot': 'సెప్టోరియా ఆకు మచ్చ',
  'Rice Blast': 'వరి బ్లాస్ట్',
  'Rice Leaf Blight': 'వరి ఆకు తెగులు',
  'Cotton Leaf Curl': 'పత్తి ఆకు మడత',
  'Chilli Leaf Spot': 'మిర్చి ఆకు మచ్చ',
  'Chilli Leaf Curl': 'మిర్చి ఆకు మడత',
  'Maize Leaf Blight': 'మొక్కజొన్న ఆకు తెగులు',
  'Maize Rust': 'మొక్కజొన్న తుప్పు',
  // Crop names (used by pickers and the plant card)
  'Tomato': 'టమాటా',
  'Rice': 'వరి',
  'Cotton': 'పత్తి',
  'Chilli': 'మిర్చి',
  'Maize': 'మొక్కజొన్న',
};

const Map<String, String> _teLevels = {
  'LOW': 'తక్కువ',
  'MEDIUM': 'మధ్యస్థం',
  'HIGH': 'అధిక',
  'CRITICAL': 'కీలకం',
  'low': 'తక్కువ',
  'medium': 'మధ్యస్థం',
  'high': 'అధిక',
};

const Map<String, String> _hiDiseases = {
  'Healthy': 'स्वस्थ',
  'Early Blight': 'अर्ली ब्लाइट',
  'Late Blight': 'लेट ब्लाइट',
  'Bacterial Spot': 'बैक्टीरियल स्पॉट',
  'Leaf Mold': 'लीफ मोल्ड',
  'Tomato Leaf Mold': 'टमाटर लीफ मोल्ड',
  'Septoria Leaf Spot': 'सेप्टोरिया धब्बा',
  'Rice Blast': 'धान ब्लास्ट',
  'Rice Leaf Blight': 'धान पत्ती झुलसा',
  'Cotton Leaf Curl': 'कपास पत्ती कर्ल',
  'Chilli Leaf Spot': 'मिर्च पत्ती धब्बा',
  'Chilli Leaf Curl': 'मिर्च पत्ती कर्ल',
  'Maize Leaf Blight': 'मक्का पत्ती झुलसा',
  'Maize Rust': 'मक्का रतुआ',
  // Crop names (used by pickers and the plant card)
  'Tomato': 'टमाटर',
  'Rice': 'धान',
  'Cotton': 'कपास',
  'Chilli': 'मिर्च',
  'Maize': 'मक्का',
};

const Map<String, String> _hiLevels = {
  'LOW': 'कम',
  'MEDIUM': 'मध्यम',
  'HIGH': 'उच्च',
  'CRITICAL': 'गंभीर',
  'low': 'कम',
  'medium': 'मध्यम',
  'high': 'उच्च',
};

const Map<String, String> _hi = {
  'SIMULATED DATA - development data, not live sensors':
      'सिमुलेटेड डेटा - विकास डेटा, लाइव सेंसर नहीं',
  'Backend unreachable - SIMULATED result shown':
      'बैकएंड उपलब्ध नहीं है - सिमुलेटेड परिणाम दिखाया गया',
  'DEVELOPMENT MODEL - demo disease result, not a trained model':
      'डेवलपमेंट मॉडल - डेमो रोग परिणाम, प्रशिक्षित मॉडल नहीं',
  'This is an estimate based on current conditions and weather trends, not a guaranteed forecast.':
      'यह वर्तमान परिस्थितियों और मौसम के रुझान पर आधारित अनुमान है, निश्चित पूर्वानुमान नहीं।',
  'Leaf Analysis': 'पत्ती विश्लेषण',
  'Current Risk': 'वर्तमान जोखिम',
  'Future Risk (48h)': 'भविष्य का जोखिम (48 घंटे)',
  'RISK OUTLOOK': 'जोखिम का अनुमान',
  'Crop: Tomato': 'फसल: टमाटर',
  'WHY?': 'क्यों?',
  'WHAT SHOULD I DO?': 'मुझे क्या करना चाहिए?',
  'Why?': 'क्यों?',
  'WHY THIS RISK?': 'यह जोखिम क्यों?',
  'Contributing Factors': 'प्रभावित करने वाले कारण',
  'The Details': 'विवरण',
  'What we saw': 'हमने क्या देखा',
  'Environment': 'पर्यावरण',
  'Weather': 'मौसम',
  'History': 'इतिहास',
  'Possible alternatives': 'संभावित विकल्प',
  'Observed': 'देखे गए लक्षण',
  'Inferred': 'अनुमान',
  'Supported by context': 'संदर्भ से समर्थित',
  'Environmental connection': 'पर्यावरणीय संबंध',
  'Uncertain': 'अनिश्चित',
  'Risk': 'जोखिम',
  'Severity assessment': 'गंभीरता का आकलन',
  'Treatment and management': 'उपचार और प्रबंधन',
  'What to do now': 'अभी क्या करें',
  'Next 3-7 days': 'अगले 3-7 दिन',
  'Prevention': 'रोकथाम',
  'What to monitor': 'क्या निगरानी करें',
  'When to contact an expert': 'विशेषज्ञ से कब संपर्क करें',
  'AI Confidence': 'AI का विश्वास स्तर',
  'confidence': 'विश्वास',
  'Risk score': 'जोखिम स्कोर',
  'Why': 'क्यों',
  'AI Explanation': 'AI विवरण',
  'What to do': 'क्या करें',
  'Loading past scans...': 'पिछले स्कैन लोड हो रहे हैं...',
  'Sample alerts - driven by the live risk engine in backend mode':
      'नमूना चेतावनियाँ - बैकएंड के लाइव जोखिम इंजन द्वारा संचालित',
  'Environmental Conditions': 'पर्यावरणीय परिस्थितियाँ',
  'Full forecast': 'पूरा पूर्वानुमान',
  'Recent Alert': 'हाल की चेतावनी',
  'All alerts': 'सभी चेतावनियाँ',
  'Recent scans': 'हाल के स्कैन',
  'View all': 'सभी देखें',
  'Early Blight detected and conditions favor spread.':
      'अर्ली ब्लाइट पाया गया है और परिस्थितियाँ इसके फैलाव के अनुकूल हैं।',
  'Device:': 'डिवाइस:',
  'Backend': 'बैकएंड',
  'Temperature / Humidity': 'तापमान / नमी',
  'Soil moisture': 'मिट्टी की नमी',
  'Light (LDR)': 'प्रकाश (LDR)',
  'What To Do?': 'क्या करें?',
  'SEE  ·  UNDERSTAND  ·  PREDICT  ·  PREVENT':
      'देखें  ·  समझें  ·  अनुमान लगाएँ  ·  रोकथाम करें',
  'Home': 'होम',
  'Device': 'डिवाइस',
  'Alerts': 'चेतावनियाँ',
  'Scan': 'स्कैन',
  'Recommendations': 'सुझाव',
  'CROP HEALTH': 'फसल स्वास्थ्य',
  'AI Insight': 'AI जानकारी',
  'Details': 'विवरण',
  'Humidity': 'नमी',
  'Soil Moisture': 'मिट्टी की नमी',
  'Temperature': 'तापमान',
  'Source:': 'स्रोत:',
  'No alerts': 'कोई चेतावनी नहीं',
  'Everything looks fine on your farm right now.':
      'अभी आपके खेत में सब कुछ ठीक दिख रहा है।',
  'Loading your farm...': 'आपका खेत लोड हो रहा है...',
  'OFFLINE - showing saved simulated data':
      'ऑफलाइन - सिमुलेटेड डेटा दिखाया जा रहा है',
  'Device Status': 'डिवाइस स्थिति',
  'Connection': 'कनेक्शन',
  'Sensors': 'सेंसर',
  'Status': 'स्थिति',
  'Data source': 'डेटा स्रोत',
  'Simulated feed active': 'सिमुलेटेड फीड सक्रिय है',
  'SIMULATED (not live ESP32)': 'सिमुलेटेड (लाइव ESP32 नहीं)',
  'See Crop Health': 'फसल स्वास्थ्य देखें',
  'Understand the Risk': 'जोखिम समझें',
  "Predict What's Next": 'आगे क्या होगा, अनुमान लगाएँ',
  'Know What To Do': 'क्या करना है जानें',
  'Take a photo of your crop leaf. Our AI checks it for disease in seconds.':
      'अपनी फसल की पत्ती की तस्वीर लें। हमारा AI कुछ सेकंड में रोग की जाँच करेगा।',
  'Weather, soil and air conditions around your crop give the full picture.':
      'फसल के आसपास का मौसम, मिट्टी और हवा की स्थिति पूरी जानकारी देती है।',
  'See if the risk will rise in the coming days - before it happens.':
      'देखें कि आने वाले दिनों में जोखिम बढ़ेगा या नहीं।',
  'Get simple, clear steps to protect your crop.':
      'अपनी फसल की सुरक्षा के लिए सरल और स्पष्ट कदम पाएँ।',
  'Skip': 'छोड़ें',
  'Next': 'आगे',
  'Get started': 'शुरू करें',
  'Welcome to AgriSentry AI': 'AgriSentry AI में आपका स्वागत है',
  'Tell us your name so we can greet you on your farm dashboard.':
      'अपना नाम बताइए ताकि हम आपके फार्म डैशबोर्ड पर आपका अभिवादन कर सकें।',
  'Your name': 'आपका नाम',
  'Setting up your farm...': 'आपका खेत तैयार हो रहा है...',
  'Continue': 'जारी रखें',
  'Select language': 'भाषा चुनें',
  'Camera or gallery is unavailable on this platform. Please choose an image from a supported device.':
      'इस प्लेटफॉर्म पर कैमरा या गैलरी उपलब्ध नहीं है। कृपया समर्थित डिवाइस चुनें।',
  'The selected image could not be read. Please choose another image.':
      'चुनी गई तस्वीर पढ़ी नहीं जा सकी। कृपया दूसरी तस्वीर चुनें।',
  'The selected image is empty or unavailable. Please choose another image.':
      'चुनी गई तस्वीर खाली या अनुपलब्ध है। कृपया दूसरी तस्वीर चुनें।',
  'Please choose a JPG, PNG, or WebP crop image.':
      'कृपया JPG, PNG या WebP फसल की तस्वीर चुनें।',
  'Camera permission is required to take a crop photo. You can enable it in Settings or choose an existing image.':
      'फसल की तस्वीर लेने के लिए कैमरा अनुमति आवश्यक है। आप सेटिंग्स में अनुमति दें या मौजूदा तस्वीर चुनें।',
  'Camera is not available on this device. You can choose a crop image from your gallery instead.':
      'इस डिवाइस पर कैमरा उपलब्ध नहीं है। इसके बजाय गैलरी से फसल की तस्वीर चुन सकते हैं।',
  'The image is no longer available. Please capture or choose it again.':
      'तस्वीर अब उपलब्ध नहीं है। कृपया फिर से तस्वीर लें या चुनें।',
  'Read aloud': 'ज़ोर से पढ़ें',
  'Stop': 'रोकें',
  'Loading...': 'लोड हो रहा है...',
  'No scans yet': 'अभी कोई स्कैन नहीं है',
  'DO NOW': 'अभी करें',
  'MANAGE': 'प्रबंधन',
  'PREVENT': 'रोकथाम',
  'MONITOR': 'निगरानी',
  'WATER': 'सिंचाई',
  'ENVIRONMENT': 'पर्यावरण',
  'Soil is very wet': 'मिट्टी बहुत गीली है',
  'Soil is dry; the plant is under stress': 'मिट्टी सूखी है; पौधा तनाव में है',
  'Leaves stayed wet for a long time': 'पत्तियाँ लंबे समय तक गीली रहीं',
  'Rain was recorded recently': 'हाल में बारिश हुई है',
  'Conditions look normal right now': 'अभी परिस्थितियाँ सामान्य हैं',
  'The leaf looks healthy': 'पत्ती स्वस्थ दिखती है',
  'These wet, warm conditions help disease spread':
      'ये गीली और गर्म परिस्थितियाँ रोग फैलने में मदद करती हैं',
  'These warm, wet conditions help disease spread':
      'ये गर्म और गीली परिस्थितियाँ रोग फैलने में मदद करती हैं',
  'Rain is expected soon, which can increase the risk':
      'जल्द बारिश की संभावना है, जिससे जोखिम बढ़ सकता है',
  'Inspect the affected leaves': 'प्रभावित पत्तियों की जाँच करें',
  'Remove badly infected leaves': 'बहुत संक्रमित पत्तियों को हटाएँ',
  'Healthy': 'स्वस्थ',
  'ACTIVE': 'सक्रिय',
  'OK': 'ठीक है',
  'Farmer': 'किसान',
  'Disease': 'रोग',
  'Health': 'स्वास्थ्य',
  'Rainfall': 'वर्षा',
  'Light': 'प्रकाश',
  'Farm warning': 'खेत की चेतावनी',
  'Scan Crop': 'फसल स्कैन करें',
  'No leaf photo yet': 'अभी पत्ती की तस्वीर नहीं है',
  'Camera': 'कैमरा',
  'Gallery': 'गैलरी',
  'For the best result:': 'बेहतर परिणाम के लिए:',
  'TAKE A PHOTO FIRST': 'पहले तस्वीर लें',
  'ANALYZE THIS LEAF': 'इस पत्ती का विश्लेषण करें',
  'Reading sensors...': 'सेंसर पढ़े जा रहे हैं...',
  'Last updated:': 'अंतिम अपडेट:',
  'Temperature (recent readings)': 'तापमान (हाल की रीडिंग)',
  'Humidity (recent readings)': 'नमी (हाल की रीडिंग)',
  'Soil Moisture (recent readings)': 'मिट्टी की नमी (हाल की रीडिंग)',
  'DEVICE STATUS': 'डिवाइस स्थिति',
  'Right Now': 'अभी',
  'Not enough readings yet for a chart.':
      'चार्ट के लिए अभी पर्याप्त रीडिंग नहीं हैं।',
  'Scanning leaf...': 'पत्ती स्कैन की जा रही है...',
  'Checking visible symptoms...': 'दिखने वाले लक्षणों की जाँच हो रही है...',
  'Analyzing crop health...': 'फसल के स्वास्थ्य का विश्लेषण हो रहा है...',
  'Combining environmental conditions...':
      'पर्यावरणीय परिस्थितियों को जोड़ा जा रहा है...',
  'Preparing your crop health report...':
      'आपकी फसल स्वास्थ्य रिपोर्ट तैयार हो रही है...',
  'Our AI is looking at your leaf and your field conditions.':
      'हमारा AI आपकी पत्ती और खेत की परिस्थितियों का विश्लेषण कर रहा है।',
  'RETAKE PHOTO': 'तस्वीर फिर से लें',
  'NOW': 'अभी',
  'Rain expected soon. Increased humidity may increase disease risk. Check that leaves can dry quickly and consider scanning a leaf after the rain.':
      'जल्द बारिश की संभावना है। बढ़ी हुई नमी से रोग का जोखिम बढ़ सकता है। जाँचें कि पत्तियाँ जल्दी सूख सकें और बारिश के बाद पत्ती स्कैन करने पर विचार करें।',
  'Weather outlook is stable or improving. Keep up normal monitoring.':
      'मौसम स्थिर या बेहतर हो रहा है। सामान्य निगरानी जारी रखें।',
  'Risk intelligence': 'जोखिम जानकारी',
  'VIEW RISK': 'जोखिम देखें',
  'Scan crop': 'फसल स्कैन करें',
  'No risk assessment yet': 'अभी जोखिम आकलन उपलब्ध नहीं है',
  'Scan a leaf to combine visual symptoms with field conditions.':
      'दृश्य लक्षणों को खेत की परिस्थितियों से जोड़ने के लिए पत्ती स्कैन करें।',
  'Why this risk level?': 'जोखिम का यह स्तर क्यों है?',
  'Estimated future risk': 'अनुमानित भविष्य का जोखिम',
  'What to consider next': 'अब क्या ध्यान रखें',
  'Review the detected symptoms': 'पता चले लक्षणों की समीक्षा करें',
  'Review recommendations': 'सुझावों की समीक्षा करें',
  'IMAGE QUALITY LOOKS GOOD': 'तस्वीर की गुणवत्ता अच्छी है',
  'IMAGE QUALITY NEEDS IMPROVEMENT': 'तस्वीर की गुणवत्ता सुधारें',
  'LIVE SENSOR DATA': 'लाइव सेंसर डेटा',
  'Backend reachable': 'बैकएंड उपलब्ध है',
  'Live connection not confirmed': 'लाइव कनेक्शन की पुष्टि नहीं हुई',
  'AVAILABLE': 'उपलब्ध',
  'NO DATA': 'डेटा उपलब्ध नहीं',

  // ----- multi-crop + plant identification (audit sections 3, 4) -----
  'Your Crop': 'आपकी फसल',
  'Add or scan a crop to get started': 'शुरू करने के लिए फसल जोड़ें या स्कैन करें',
  'Your Tomato Field': 'आपका टमाटर का खेत',
  'Your Rice Field': 'आपका धान का खेत',
  'Your Cotton Field': 'आपका कपास का खेत',
  'Your Chilli Field': 'आपका मिर्च का खेत',
  'Your Maize Field': 'आपका मक्का का खेत',
  'Your crop': 'आपकी फसल',
  'Select your crop above so the AI uses the right knowledge.':
      'ऊपर अपनी फसल चुनें ताकि AI सही जानकारी इस्तेमाल करे।',
  'Plant': 'पौधा',
  'Selected by you': 'आपके द्वारा चयनित',
  'What to look for': 'क्या देखें',
  'Monitor': 'निगरानी करें',
  'View Technical Details': 'तकनीकी विवरण देखें',
  'Disease model status': 'रोग मॉडल स्थिति',
  'Risk engine': 'जोखिम इंजन',
  'Prediction model': 'भविष्यवाणी मॉडल',
  'VIEW FULL EXPLANATION': 'पूरी व्याख्या देखें',
  'No visible disease': 'कोई रोग नहीं दिख रहा',
  'How this works: AgriSentry AI combined the leaf image, weather, sensor readings and your recent scan history to estimate this risk using transparent, documented rules.':
      'यह कैसे काम करता है: AgriSentry AI ने पत्ती की तस्वीर, मौसम, सेंसर रीडिंग और हाल के स्कैन इतिहास को पारदर्शी, प्रलेखित नियमों से जोड़कर यह जोखिम आंका है।',
  'AI guidance supports - but does not replace - your local agricultural experts, especially when the situation is severe or uncertain.':
      'AI सलाह आपके स्थानीय कृषि विशेषज्ञों का समर्थन करती है - उनका विकल्प नहीं है, खासकर जब स्थिति गंभीर या अनिश्चित हो।',
  'Select your crop': 'अपनी फसल चुनें',

  // ----- sync + offline (audit: sections 5, 16) -----
  'Synchronization': 'सिंक्रोनाइज़ेशन',
  'Sync now': 'अभी सिंक करें',
  'Last sync': 'अंतिम सिंक',
  'Synced': 'सिंक हो गया',
  'Sync pending': 'सिंक बाकी है',
  'Syncing...': 'सिंक हो रहा है...',
  'Offline - saved on device': 'ऑफ़लाइन - डिवाइस पर सुरक्षित',
  'All analyses are saved and synced.': 'सभी विश्लेषण सहेजे और सिंक हो गए हैं।',
  'analyses waiting to sync': 'विश्लेषण सिंक होने की प्रतीक्षा में',
  'saved safely on this device. Will sync automatically when internet is available.':
      'इस डिवाइस पर सुरक्षित हैं। इंटरनेट आने पर अपने आप सिंक हो जाएंगे।',
  'Offline-first: analyses are always saved on this device first and synced when internet returns.':
      'ऑफ़लाइन-पहले: विश्लेषण हमेशा पहले इस डिवाइस पर सहेजे जाते हैं और इंटरनेट लौटने पर सिंक होते हैं।',

  // ----- weather agricultural impact (audit section 17) -----
  'Agricultural Impact': 'कृषि प्रभाव',
  'Humidity is high': 'नमी अधिक है',
  'High humidity may increase fungal disease risk. Watch leaf condition and scan a leaf if spots appear.':
      'अधिक नमी से फंगल रोग का खतरा बढ़ सकता है। पत्तियों की स्थिति देखें और धब्बे दिखें तो पत्ती स्कैन करें।',
  'Weather feeds directly into the AgriSentry AI risk engine - a scan taken now combines these conditions with the leaf image.':
      'मौसम सीधे AgriSentry AI जोखिम इंजन में जाता है - अभी किया गया स्कैन इन स्थितियों को पत्ती की तस्वीर के साथ जोड़ता है।',

  // ----- audit: knowledge base, actions and explanations -----
  '• Use daylight, not direct glare\n• Fill the frame with one leaf\n• Hold the phone steady\n• Include the spotted part of the leaf':
      '• प्रत्यक्ष चमक के बजाय दिन की रोशनी लें\n• एक पत्ती से फ्रेम भरें\n• फोन को स्थिर रखें\n• पत्ती के धब्बेदार हिस्से को शामिल करें',
  'Take a clear leaf photo in daylight, then analyze the leaf.':
      'दिन की रोशनी में पत्ती की साफ तस्वीर लें, फिर पत्ती का विश्लेषण करें।',
  'Scan a leaf to calculate risk from image + environment.':
      'तस्वीर + पर्यावरण से जोखिम जानने के लिए पत्ती स्कैन करें।',
  'Scan a leaf weekly and watch the risk on the dashboard.':
      'हर सप्ताह पत्ती स्कैन करें और डैशबोर्ड पर जोखिम देखें।',
  'Scan your first leaf to start building history.':
      'इतिहास बनाने के लिए अपनी पहली पत्ती स्कैन करें।',
  'No reliable disease detected': 'कोई विश्वसनीय रोग नहीं मिला',
  'Not selected yet': 'अभी चयनित नहीं',
  'Waiting for scan': 'स्कैन की प्रतीक्षा में',
  'Not analyzed': 'विश्लेषित नहीं किया गया',
  'Legal': 'कानूनी',
  'Privacy Policy': 'गोपनीयता नीति',
  'Terms and Conditions': 'नियम और शर्तें',
  'This document is provided in English.': 'यह दस्तावेज़ अंग्रेज़ी में दिया गया है।',
  'Sensor data unavailable': 'सेंसर डेटा उपलब्ध नहीं है',
  'Weather data unavailable': 'मौसम डेटा उपलब्ध नहीं है',
  'Backend unreachable - disease could not be determined from this image': 'बैकएंड पहुंच योग्य नहीं - इस तस्वीर से रोग निर्धारित नहीं किया जा सका',
  'Scan a leaf to get your first AI insight.': 'अपनी पहली एआई जानकारी पाने के लिए पत्ती स्कैन करें।',
  'No live weather is available right now. Values are not simulated - pull down to retry.':
      'इस समय कोई लाइव मौसम उपलब्ध नहीं है। मान कृत्रिम रूप से नहीं दिखाए जाते - पुनः प्रयास के लिए नीचे खींचें।',
  'Retry': 'पुनः प्रयास करें',
  'No ESP32 sensor readings are available right now. Values are not simulated - check the device and pull down to retry.':
      'इस समय कोई ESP32 सेंसर रीडिंग उपलब्ध नहीं है। मान कृत्रिम रूप से नहीं दिखाए जाते - डिवाइस जाँचें और पुनः प्रयास के लिए नीचे खींचें।',
  'demo_rules_v1: no trained image model is bundled, so disease cannot be determined from this photo. Provide the backend API or bundle a TFLite model for real inference.':
      'demo_rules_v1: कोई प्रशिक्षित इमेज मॉडल शामिल नहीं है, इसलिए इस तस्वीर से रोग निर्धारित नहीं किया जा सकता। वास्तविक विश्लेषण के लिए बैकएंड API या TFLite मॉडल जोड़ें।',
  'The available image evidence is not strong enough to name a disease. Environmental conditions may affect future risk, but they do not prove a current disease.':
      'रोग बताने के लिए तस्वीर के सबूत पर्याप्त मजबूत नहीं हैं। पर्यावरणीय परिस्थितियाँ भविष्य के जोखिम को प्रभावित कर सकती हैं, लेकिन वे किसी मौजूदा रोग को सिद्ध नहीं करतीं।',
  'The photo file is empty or unreadable.': 'फोटो फ़ाइल खाली या पढ़ने योग्य नहीं है।',
  'The photo looks too dark. Use daylight, not shade.':
      'फोटो बहुत गहरी है। छाया नहीं, दिन की रोशनी लें।',
  'The photo looks blurry. Hold the phone steady and retake it.':
      'फोटो धुंधली है। फोन को स्थिर रखें और दोबारा लें।',
  'The photo looks overexposed. Avoid direct glare.':
      'फोटो में ज़्यादा रोशनी है। सीधी चमक से बचें।',
  'Too dark': 'बहुत गहरी',
  'Too bright': 'बहुत चमकीली',
  'The leaf looks green and uniform with no spots or discoloration.':
      'पत्ती हरी और एकसार दिख रही है, कोई धब्बा या रंग बदलाव नहीं है।',
  'The leaf shows signs of Early Blight. The AI is 91% sure of this.':
      'पत्ती पर अर्ली ब्लाइट के लक्षण हैं। AI को इस बात 91% विश्वास है।',
  'Visual symptoms detected in the leaf image.': 'पत्ती की तस्वीर में लक्षण दिखे।',
  'Dark brown spots with concentric rings, usually starting on lower, older leaves with yellowing around them.':
      'गाढ़े भूरे धब्बे जिनमें संकेंद्रित वलय होते हैं, आमतौर पर नीचे की पुरानी पत्तियों से शुरू होकर चारों ओर पीलापन फैलता है।',
  'Small brown circular spots with lighter centers on leaves; severe spots merge and leaves drop early.':
      'पत्तियों पर हल्के केंद्र वाले छोटे भूरे गोल धब्बे; गंभीर स्थिति में धब्बे मिलकर पत्तियां जल्दी झड़ती हैं।',
  'Pale yellowish spots on the upper leaf surface with olive-green fuzzy mold underneath, in humid still air.':
      'ऊपरी पत्ती सतह पर पीले धब्बे और नीचे जैतून-हरे फफूंद, नमी भरी बंद हवा में दिखाई देते हैं।',
  'Greasy, water-soaked patches with white fuzzy growth under the leaf; spreads extremely fast in cool wet weather.':
      'चिकने, पानी से भीगे धब्बे और पत्ती के नीचे सफेद फफूंद; ठंडे गीले मौसम में बेहद तेज़ी से फैलती है।',
  'Small, dark, angular water-soaked spots that may look greasy; leaves can turn yellow and drop.':
      'छोटे, गहरे, कोनों वाले पानी से भीगे धब्बे जो चिकने लग सकते हैं; पत्तियां पीली होकर झड़ सकती हैं।',
  'Wavy-edged yellow to straw-colored lesions running along leaf margins or veins, often after heavy rain or wind.':
      'पत्ती के किनारों या नसों पर लहरदार किनारों वाले पीले-पुआल रंग के धब्बे, अक्सर तेज़ बारिश या हवा के बाद।',
  'Diamond-shaped spots with grey centers and brown edges on leaves; nodes or panicles may turn brown and break.':
      'पत्तियों पर हीरे के आकार के धब्बे - स्लेटी केंद्र और भूरे किनारे; गांठें या बालियां भूरी होकर टूट सकती हैं।',
  'Long, cigar-shaped grey-green to tan lesions running along the leaves, growing larger in humid weather.':
      'पत्तियों पर सिगार के आकार के स्लेटी-हरे से भूरे धब्बे, नमी भरे मौसम में बड़े होते जाते हैं।',
  'Young leaves curl and pucker, plants look stunted with shortened internodes.':
      'नई पत्तियां मुड़कर सिकुड़ जाती हैं, पौधे रुंधे हुए और गांठों के बीच कम दूरी के साथ दिखते हैं।',
  'Small, raised, cinnamon-brown pustules scattered on both leaf surfaces that rub off like powder.':
      'दोनों पत्ती सतहों पर बिखरे छोटे, उभरे दालचीनी-भूरे फुंसे जो पाउडर की तरह रगड़कर निकल जाते हैं।',
  'Upward or downward curling of leaves with thickened veins; leaves look small, leathery and dark.':
      'मोटी नसों के साथ पत्तियों का ऊपर-नीचे मुड़ना; पत्तियां छोटी, चमड़े जैसी और गहरी दिखती हैं।',
  'Many small circular spots with dark borders and tiny black dots (fruiting bodies) in the center, on lower leaves first.':
      'गहरे किनारों और केंद्र में छोटे काले बिंदुओं वाले कई छोटे गोल धब्बे, पहले नीचे की पत्तियों पर।',
  'Spread of spots to upper leaves': 'ऊपरी पत्तियों तक धब्बों का फैलाव',
  'Number of new spots': 'नए धब्बों की संख्या',
  'Lesion size and count': 'धब्बों का आकार और संख्या',
  'Pustule density': 'फुंसों की संख्या',
  'New spots': 'नए धब्बे',
  'New spots on young leaves': 'नई पत्तियों पर नए धब्बे',
  'New spots or discoloration': 'नए धब्बे या रंग बदलाव',
  'New water-soaked patches': 'नए पानी से भीगे धब्बे',
  'New curled leaves': 'नई मुड़ी पत्तियां',
  'New diamond-shaped spots': 'नए हीरे आकार के धब्बे',
  'Yellowing leaf margins': 'पत्ती किनारों का पीलापन',
  'Leaf drop': 'पत्तियां झड़ना',
  'Leaf condition': 'पत्तियों की स्थिति',
  'Leaf wetness': 'पत्तियों की नमी',
  'Leaf Wetness': 'पत्तियों की नमी',
  'Leaves stayed wet for a long time.': 'पत्तियां लंबे समय तक गीली रहीं।',
  'Under-leaf mold growth': 'पत्ती के नीचे फफूंद',
  'High humidity': 'अधिक नमी',
  'High soil moisture': 'अधिक मिट्टी की नमी',
  'Temperature and humidity': 'तापमान और नमी',
  'Field water level': 'खेत में पानी का स्तर',
  'Whitefly counts': 'सफेद मक्खी की संख्या',
  'Whitefly or thrips presence': 'सफेद मक्खी या थ्रिप्स की मौजूदगी',
  'Plant vigor': 'पौधे की जीवन शक्ति',
  'Air movement': 'हवा का बहाव',
  'Mark how many plants show lesions to track spread at the next check.':
      'अगली जांच में फैलाव ट्रैक करने के लिए गिनें कितने पौधों पर धब्बे हैं।',
  'Scout several field spots': 'खेत के कई स्थानों की जांच करें',
  'Inspect the field edges': 'खेत के किनारों की जांच करें',
  'Check the lower canopy': 'निचली परत की पत्तियां देखें',
  'Monitor daily': 'रोज़ निगरानी करें',
  'Regular monitoring': 'नियमित निगरानी',
  'Inspect for whiteflies and thrips': 'सफेद मक्खी और थ्रिप्स की जांच करें',
  'Check for whitefly': 'सफेद मक्खी की जांच करें',
  'Keep leaves dry': 'पत्तियों को सूखा रखें',
  'Keep up good practices': 'अच्छी प्रथाएं जारी रखें',
  'Water the crop': 'फसल को पानी दें',
  'Water at the base, not the leaves': 'पत्तियों पर नहीं, जड़ के पास पानी दें',
  'Reduce watering for now': 'फिलहाल पानी कम करें',
  'Drain standing water briefly': 'जमा पानी कुछ देर के लिए निकालें',
  'Manage water carefully': 'पानी का सावधानी से प्रबंधन करें',
  'Remove infected leaves': 'संक्रमित पत्तियां हटाएं',
  'Remove spotted leaves': 'धब्बेदार पत्तियां हटाएं',
  'Remove heavily affected leaves': 'ज़्यादा प्रभावित पत्तियां हटाएं',
  'Remove infected lower leaves': 'निचली संक्रमित पत्तियां हटाएं',
  'Remove visibly infected plants': 'दिखाई देने वाले संक्रमित पौधे हटाएं',
  'Remove and destroy moldy leaves. Do not leave them in the field.':
      'फफूंद वाली पत्तियां हटाकर नष्ट करें। खेत में न छोड़ें।',
  'Remove and destroy badly curled plants': 'बुरी तरह मुड़े पौधे हटाकर नष्ट करें',
  'Remove severely curled plants': 'बुरी तरह मुड़े पौधे हटाएं',
  'Remove infected plants so whiteflies cannot spread the virus onward.':
      'संक्रमित पौधे हटाएं ताकि सफेद मक्खी वायरस आगे न फैला सके।',
  'Remove volunteer hosts': 'स्वयं उगे पौधों (होस्ट) को हटाएं',
  'Pick off heavily spotted leaves and destroy them. Do not compost them.':
      'ज़्यादा धब्बेदार पत्तियां तोड़कर नष्ट करें। खाद में न डालें।',
  'Prune affected leaves with clean tools and dispose of them away from the field.':
      'साफ औज़ारों से प्रभावित पत्तियां काटें और खेत से दूर नष्ट करें।',
  'Prune spotted leaves with clean tools and dispose of them away from the field.':
      'साफ औज़ारों से धब्बेदार पत्तियां काटें और खेत से दूर नष्ट करें।',
  'Destroy badly infected plants to protect healthy neighbors.':
      'स्वस्थ पौधों की रक्षा के लिए बुरी तरह संक्रमित पौधे नष्ट करें।',
  'Do not plant tomato or potato in the same spot next season.':
      'अगले मौसम उसी जगह टमाटर या आलू न लगाएं।',
  'Rotate crops': 'फसल चक्र अपनाएं',
  'Rotate crops next season': 'अगले मौसम फसल बदलें',
  'Choose tolerant varieties next season': 'अगले मौसम सहनशील किस्में चुनें',
  'Use healthy seedlings': 'स्वस्थ पौधे (पौध रोपण) इस्तेमाल करें',
  'Start with certified, disease-free nursery stock when available.':
      'उपलब्ध हो तो प्रमाणित, रोग-मुक्त नर्सरी पौधों से शुरू करें।',
  'Ensure good field ventilation': 'खेत में हवा का अच्छा बहाव सुनिश्चित करें',
  'Ensure ventilation': 'हवा का बहाव सुनिश्चित करें',
  'Improve airflow': 'हवा का बहाव सुधारें',
  'Improve airflow in the canopy': 'फसल के भीतर हवा का बहाव सुधारें',
  'Improve air circulation': 'हवा का आवागमन बढ़ाएं',
  'Open up dense foliage and improve ventilation - Leaf Mold thrives in still, humid air.':
      'घनी पत्तियों को खोलें और हवा का बहाव बढ़ाएं - लीफ मोल्ड बंद, नम हवा में तेज़ी से फैलती है।',
  'Reduce humidity inside the crop': 'फसल के भीतर नमी कम करें',
  'Avoid overhead watering': 'पत्तियों के ऊपर से पानी देने से बचें',
  'Avoid overhead irrigation': 'फव्वारे से सिंचाई से बचें',
  'Avoid overhead watering until the outbreak is under control.':
      'रोग नियंत्रण में आने तक पत्तियों के ऊपर पानी देने से बचें।',
  'Avoid excess nitrogen fertilizer': 'ज़रूरत से ज़्यादा नाइट्रोजन खाद डालने से बचें',
  'Avoid heavy nitrogen stress': 'भारी नाइट्रोजन दबाव से बचें',
  'Avoid wounding plants': 'पौधों में घाव (चोट) से बचें',
  'Disinfect tools and hands': 'औज़ारों और हाथों को कीटाणुरहित करें',
  'Disinfect tools and hands between plants.': 'पौधों के बीच औज़ार और हाथ कीटाणुरहित करें।',
  'Apply a suitable fungicide': 'उपयुक्त फंगीसाइड छिड़काव करें',
  'Apply a suitable bactericide': 'उपयुक्त बैक्टीरीसाइड छिड़काव करें',
  'Apply recommended fungicide urgently': 'अनुशंसित फंगीसाइड तुरंत छिड़काव करें',
  'Act immediately - Late Blight spreads fast': 'तुरंत कार्रवाई करें - लेट ब्लाइट तेज़ी से फैलती है',
  'Use a copper-based or recommended fungicide, following the label. Confirm with your agricultural officer.':
      'लेबल अनुसार कॉपर-आधारित या अनुशंसित फंगीसाइड इस्तेमाल करें। अपने कृषि अधिकारी से पुष्टि करें।',
  'Copper bactericides help limit spread. Confirm dosage with your dealer or officer.':
      'कॉपर बैक्टीरीसाइड फैलाव रोकने में मदद करते हैं। खुराक डीलर या अधिकारी से पुष्टि करें।',
  'Late Blight can destroy a crop within days in cool, wet weather. Consult your agricultural officer for the right product.':
      'ठंडे, गीले मौसम में लेट ब्लाइट कुछ दिनों में फसल नष्ट कर सकती है। सही उत्पाद के लिए अपने कृषि अधिकारी से सलाह लें।',
  'Yellow sticky traps and clean field edges reduce whitefly numbers. Confirm treatments locally.':
      'पीले चिपचिपे जाल और साफ खेत किनारे सफेद मक्खी घटाते हैं। उपचार स्थानीय रूप से पुष्टि करें।',
  'Sticky traps and regular monitoring keep vectors low. Confirm treatments locally.':
      'चिपचिपे जाल और नियमित निगरानी वाहक कम रखते हैं। उपचार स्थानीय रूप से पुष्टि करें।',
  'Control whitefly pressure': 'सफेद मक्खी का दबाव नियंत्रित करें',
  'Manage sucking pests early': 'चूषक कीटों को जल्दी नियंत्रित करें',
  'Old crop residue and weeds harbor whiteflies between seasons.':
      'पुरानी फसल अवशेष और खरपतवार मौसमों के बीच सफेद मक्खी छिपाए रखते हैं।',
  'Manage field residue': 'खेत के अवशेषों का प्रबंधन करें',
  'Infected residue carries rust to the next crop.':
      'संक्रमित अवशेष अगली फसल में रतुआ (रस्ट) ले जाते हैं।',
  'Maize-after-maize fields build up spores in the residue.':
      'लगातार मक्का वाले खेतों में अवशेषों में बीजाणु जमा हो जाते हैं।',
  'Rust-tolerant hybrids are the most durable control.':
      'रतुआ-सहनशील संकर किस्में सबसे टिकाऊ नियंत्रण हैं।',
  'Rust builds quickly - count pustules on a few plants across the field.':
      'रतुआ तेज़ी से बढ़ती है - खेत भर के कुछ पौधों पर फुंसे गिनें।',
  'Balanced fertilization': 'संतुलित उर्वरक',
  'Balanced plant density reduces humid, still air inside the canopy.':
      'संतुलित पौध घनत्व फसल के भीतर नम, बंद हवा कम करता है।',
  'Wider spacing between seedlings reduces humid, still air.':
      'पौधों के बीच ज़्यादा दूरी नम, बंद हवा कम करती है।',
  'Wider spacing helps leaves dry quickly after rain or watering.':
      'ज़्यादा दूरी से बारिश या सिंचाई के बाद पत्तियां जल्दी सूखती हैं।',
  'Space plants and remove weeds so leaves dry faster in humid weather.':
      'नम मौसम में पत्तियां जल्दी सूखें इसके लिए पौधों की दूरी बढ़ाएं और खरपतवार हटाएं।',
  'Space plants and remove weeds so leaves dry quickly after rain.':
      'बारिश के बाद पत्तियां जल्दी सूखें इसके लिए पौधों की दूरी बढ़ाएं और खरपतवार हटाएं।',
  'Space plants properly and remove weeds so leaves dry faster.':
      'पत्तियां जल्दी सूखें इसके लिए पौधों की उचित दूरी रखें और खरपतवार हटाएं।',
  'Proper plant spacing and morning watering keep leaves and air drier.':
      'उचित पौध दूरी और सुबह की सिंचाई से पत्तियां और हवा सूखी रहती है।',
  'Mulch around the plants': 'पौधों के चारों ओर मल्चिंग करें',
  'Mulch the beds': 'क्यारियों पर मल्चिंग करें',
  'Mulch blocks spores splashing from soil onto leaves during rain or watering.':
      'मल्चिंग बारिश या सिंचाई में मिट्टी से पत्तियों पर छलकने वाले बीजाणु रोकती है।',
  'Mulch reduces spore splash from the soil surface.':
      'मल्चिंग मिट्टी की सतह से बीजाणु छलकना कम करती है।',
  'Mulching stops fungal spores in the soil from splashing onto leaves during rain.':
      'मल्चिंग बारिश में मिट्टी के फंगल बीजाणुओं का पत्तियों पर छलकना रोकती है।',
  'Splashing water spreads leaf spot spores plant to plant.':
      'छलकता पानी धब्बा रोग के बीजाणु एक पौधे से दूसरे पौधे तक फैलाता है।',
  'Splashing water spreads the bacteria leaf to leaf.':
      'छलकता पानी जीवाणु को एक पत्ती से दूसरी पत्ती तक फैलाता है।',
  'Wet leaves spread Septoria - use drip or base watering.':
      'गीली पत्तियां सेप्टोरिया फैलाती हैं - ड्रिप या जड़ में पानी दें।',
  'Use drip or base watering early in the day so leaves stay dry.':
      'दिन में जल्दी ड्रिप या जड़ में पानी दें ताकि पत्तियां सूखी रहें।',
  'Keep the field from drying out completely; stressed rice is more prone to blast.':
      'खेत को पूरी तरह सूखने न दें; तनावग्रस्त धान में ब्लास्ट अधिक लगती है।',
  'Greenhouses and polytunnels need vents opened when humidity rises.':
      'ग्रीनहाउस और पॉलीटनल में नमी बढ़ने पर वेंट खोलें।',
  'Bacteria enter through cuts from tools, insects or wind damage.':
      'जीवाणु औज़ारों, कीड़ों या हवा से हुई कटाव के जरिए भीतर जाते हैं।',
  'Bacteria spread through wounds and wet contact.':
      'जीवाणु घावों और गीले संपर्क से फैलते हैं।',
  'The fungus spreads on wet clothes, tools and hands.':
      'फफूंद गीले कपड़ों, औज़ारों और हाथों से फैलती है।',
  'Bacterial leaf blight spreads fast in warm, wet fields - a short drain can slow it.':
      'जीवाणु पत्ती झुलसा गर्म, गीले खेतों में तेज़ी से फैलता है - थोड़े समय के लिए पानी निकालने से धीमा पड़ता है।',
  'Uproot badly affected plants to limit spread through the water.':
      'पानी के जरिए फैलाव रोकने के लिए बुरी तरह प्रभावित पौधे उखाड़ फेंकें।',
  'Leaf curl is spread by whiteflies - inspect the underside of leaves.':
      'पत्ती कुचक्री सफेद मक्खी से फैलती है - पत्तियों की निचली सतह देखें।',
  'Leaf curl viruses are spread by sucking pests - check leaf undersides.':
      'पत्ती कुचक्री वायरस चूषक कीटों से फैलते हैं - पत्तियों की निचली सतह देखें।',
  'Excess nitrogen favors bacterial blight development.':
      'ज़रूरत से ज़्यादा नाइट्रोजन जीवाणु झुलसे को बढ़ाता है।',
  'Heavy nitrogen makes soft, dense growth that blast attacks easily.':
      'भारी नाइट्रोजन से नरम, घनी वृद्धि होती है जिस पर ब्लास्ट आसानी से हमला करती है।',
  'Blast usually starts in shaded, humid corners - check them first.':
      'ब्लास्ट अक्सर छायादार, नम कोनों से शुरू होती है - पहले वहीं जांच करें।',
  'Northern corn leaf blight starts on lower leaves and moves upward.':
      'उत्तरी कॉर्न पत्ती झुलसा निचली पत्तियों से शुरू होकर ऊपर जाता है।',
  'Check lower, older leaves first - Early Blight usually starts there.':
      'पहले निचली पुरानी पत्तियां देखें - अर्ली ब्लाइट अक्सर वहीं से शुरू होती है।',
  'Check the whole field today and remove infected plants and leaves.':
      'आज पूरे खेत की जांच करें और संक्रमित पौधे-पत्तियां हटाएं।',
  'Check the crop every day and follow the actions above.':
      'रोज़ फसल की जांच करें और ऊपर दी गई कार्रवाइयां करें।',
  'Conditions are currently favorable - keep monitoring regularly.':
      'स्थितियां अभी अनुकूल हैं - नियमित निगरानी जारी रखें।',
  'Conditions favor disease development, but no strong increase is expected in the next 48 hours.':
      'स्थितियां रोग विकास के अनुकूल हैं, पर अगले 48 घंटों में बड़ी वृद्धि की संभावना नहीं है।',
  'Conditions look normal right now.': 'स्थितियां अभी सामान्य दिख रही हैं।',
  'These conditions are within a normal range.': 'ये स्थितियां सामान्य सीमा में हैं।',
  'These wet, warm conditions help disease spread.':
      'ये गीली, गर्म स्थितियां रोग फैलने में मदद करती हैं।',
  'Humidity is high (82%).': 'नमी अधिक है (82%)।',
  'Humidity is within a favorable range for some diseases.':
      'नमी कुछ रोगों के लिए अनुकूल सीमा में है।',
  'Humidity is within a typical range.': 'नमी सामान्य सीमा में है।',
  'Humidity stayed above 80% for hours. Watch for leaf diseases.':
      'नमी घंटों 80% से ऊपर रही। पत्ती रोगों पर नज़र रखें।',
  'Temperature (27 C) favors disease development.':
      'तापमान (27°C) रोग विकास के अनुकूल है।',
  'Temperature can favor some leaf diseases.': 'तापमान कुछ पत्ती रोगों को बढ़ा सकता है।',
  'Temperature is not an extra warning by itself.': 'तापमान अपने आप कोई अतिरिक्त चेतावनी नहीं है।',
  'Temperature is 27 C, humidity 82%. These warm, wet conditions help disease spread.':
      'तापमान 27°C, नमी 82%। ये गर्म, गीली स्थितियां रोग फैलने में मदद करती हैं।',
  'High soil moisture can keep leaves wet longer.':
      'अधिक मिट्टी की नमी पत्तियों को लंबे समय गीला रख सकती है।',
  'Soil moisture looks typical.': 'मिट्टी की नमी सामान्य है।',
  'Soil is very wet.': 'मिट्टी बहुत गीली है।',
  'Soil is very wet. Extra watering keeps leaves and roots damp and helps disease.':
      'मिट्टी बहुत गीली है। अतिरिक्त पानी पत्तियां और जड़ें गीला रखकर रोग बढ़ाता है।',
  'Soil moisture is low and the plant is under stress. Water at the base.':
      'मिट्टी की नमी कम है और पौधा तनाव में है। जड़ के पास पानी दें।',
  'Soil is dry; the plant is under stress.': 'मिट्टी सूखी है; पौधा तनाव में है।',
  'Soil is dry; the plant may be under stress.': 'मिट्टी सूखी है; पौधा तनाव में हो सकता है।',
  'Rain in the next 24h may increase disease risk.':
      'अगले 24 घंटों में बारिश से रोग जोखिम बढ़ सकता है।',
  'Rain is expected soon, which can increase the risk.':
      'जल्द बारिश की संभावना है, जिससे जोखिम बढ़ सकता है।',
  'Rain was recorded recently.': 'हाल में बारिश दर्ज हुई।',
  'Rain or worsening weather may increase disease pressure.':
      'बारिश या बिगड़ता मौसम रोग का दबाव बढ़ा सकता है।',
  'Rain or worsening weather may increase disease risk. Check that leaves can dry quickly.':
      'बारिश या बिगड़ता मौसम रोग जोखिम बढ़ा सकता है। सुनिश्चित करें कि पत्तियां जल्दी सूखें।',
  'The weather is expected to improve.': 'मौसम में सुधार की संभावना है।',
  'The weather is expected to stay stable.': 'मौसम स्थिर रहने की संभावना है।',
  'The weather outlook is getting worse (more rain expected).':
      'मौसम का बिगड़ना संभावित है (अधिक बारिश की आशंका)।',
  'Weather outlook is stable or improving.': 'मौसम स्थिर या सुधार की ओर है।',
  'HIGH HUMIDITY and rain can favor disease development. This is an estimate, not a guarantee.':
      'अधिक नमी और बारिश रोग विकास के अनुकूल हो सकते हैं। यह अनुमान है, गारंटी नहीं।',
  'Environmental condition may increase disease risk.':
      'पर्यावरणीय स्थिति रोग जोखिम बढ़ा सकती है।',
  'Low light can slow drying after rain.': 'कम रोशनी बारिश के बाद सूखना धीमा कर सकती है।',
  'Light level looks usable for the crop.': 'प्रकाश स्तर फसल के लिए उपयुक्त है।',
  'Humid conditions help it spread.': 'नमी भरी स्थितियां इसके फैलाव में मदद करती हैं।',
  'The weather outlook may help it spread.': 'मौसम का रुझान इसके फैलाव में मदद कर सकता है।',
  'Conditions should be monitored.': 'स्थितियों की निगरानी करनी चाहिए।',
  'A recent scan already showed high risk.': 'हाल के स्कैन में पहले ही उच्च जोखिम दिखा।',
  'Your crop currently looks healthy, but humidity is increasing. Scan a leaf soon to be sure.':
      'आपकी फसल अभी स्वस्थ दिख रही है, पर नमी बढ़ रही है। पक्का करने के लिए जल्द पत्ती स्कैन करें।',
  'Your crop is at high risk (78/100). Early Blight was detected and humid, warm weather helps it spread.':
      'आपकी फसल में उच्च जोखिम है (78/100)। अर्ली ब्लाइट पाई गई है और नम, गर्म मौसम इसके फैलाव में मदद कर रहा है।',
  'No disease was detected.': 'कोई रोग नहीं पाया गया।',
  'Early Blight was detected on the leaf (91% confidence).':
      'पत्ती पर अर्ली ब्लाइट पाया गया (91% विश्वास)।',
  'High disease risk': 'उच्च रोग जोखिम',
  'Maintain steady watering, spacing and clean field conditions.':
      'नियमित सिंचाई, पौध दूरी और साफ खेत स्थितियां बनाए रखें।',
  'Note affected plant count': 'प्रभावित पौधों की संख्या नोट करें',
  'Plant identification is uncertain. Please capture a clearer image of the leaf and include the complete leaf in the frame.':
      'पौधे की पहचान अनिश्चित है। कृपया पत्ती की साफ तस्वीर लें और पूरी पत्ती फ्रेम में रखें।',
  'Remove spotted lower leaves with clean tools and destroy them away from the field.':
      'साफ औज़ारों से धब्बेदार निचली पत्तियां काटें और खेत से दूर नष्ट करें।',
  'Showing cached or simulated information. Live sensors and AI are not confirmed.':
      'कैश्ड या सिम्युलेटेड जानकारी दिख रही है। लाइव सेंसर और AI पुष्ट नहीं हैं।',
  'Stressed plants show worse rust; keep nutrition balanced. Confirm locally.':
      'तनावग्रस्त पौधों में रतुआ ज़्यादा लगती है; पोषण संतुलित रखें। स्थानीय रूप से पुष्टि करें।',
  'These are AI-generated preventive suggestions. They do not replace professional agricultural advice - consult your local agricultural officer before applying any treatment.':
      'ये AI-जनित निवारक सुझाव हैं। ये पेशेवर कृषि सलाह का विकल्प नहीं हैं - कोई भी उपचार करने से पहले अपने कृषि अधिकारी से सलाह लें।',
  'Calculated only from scans stored on this device or backend.':
      'केवल इस डिवाइस या बैकएंड पर सहेजे स्कैन से गणना की गई है।',
  'Open the explanation to understand the evidence behind this estimate.':
      'इस अनुमान के पीछे के प्रमाण समझने के लिए विवरण खोलें।',
  'Use the action list as guidance and confirm treatment decisions locally.':
      'कार्य सूची को मार्गदर्शन मानें और उपचार के निर्णय स्थानीय स्तर पर पुष्टि करें।',
  'conditions help disease spread.': 'स्थितियां रोग फैलने में मदद करती हैं।',
  'detected and humid, warm weather helps it spread.':
      'पाई गई है और नम, गर्म मौसम इसके फैलाव में मदद कर रहा है।',
  'conditions should be monitored': 'स्थितियों की निगरानी करनी चाहिए',

  // ----- audit: previously untranslated UI labels / statuses -----
  'OFFLINE': 'ऑफ़लाइन',  'SIMULATED': 'सिम्युलेटेड',
  'AI identified a different crop': 'एआई ने एक अलग फसल पहचानी',
  'Uncertain identification': 'पहचान अनिश्चित है',
  'Identification not reliable': 'पहचान भरोसेमंद नहीं है',
  'Check selected crop': 'चुनी गई फसल जाँचें',
  'Identified crop:': 'पहचानी गई फसल:',
  'CACHED / SIMULATED': 'कैश्ड / सिम्युलेटेड',
  'CONNECTED': 'जुड़ा हुआ',
  'LIVE DATA': 'लाइव डेटा',
  'Rain expected': 'बारिश संभावित',
  'AT RISK': 'जोखिम में',
  'SCAN CROP': 'फसल स्कैन करें',
  'SCAN LEAF': 'पत्ती स्कैन करें',
  'Try again': 'पुनः प्रयास करें',
  'Condition': 'स्थिति',
  'Crop': 'फसल',
  'Current risk': 'वर्तमान जोखिम',
  'Severity': 'गंभीरता',
  'Detected': 'पाया गया',
  'Disease detected': 'रोग पाया गया',
  'Disease detections': 'रोग की पहचानें',
  'Plant identification': 'पौधे की पहचान',
  'Analytics': 'विश्लेषण',
  'Multimodal analysis': 'मल्टीमोडल विश्लेषण',
  'Quick actions': 'त्वरित कार्य',
  'Total scans': 'कुल स्कैन',
  'Healthy scans': 'स्वस्थ स्कैन',
  'Average confidence': 'औसत विश्वास',
  'Average risk': 'औसत जोखिम',
  'Most detected condition': 'सबसे अधिक पाई गई स्थिति',
  'Just now': 'अभी',
  '1 day': '1 दिन',
  '2-3 days': '2-3 दिन',
  '3-5 days': '3-5 दिन',
  '7 days': '7 दिन',
  'Please enter your name': 'कृपया अपना नाम दर्ज करें',
  'Could not save your name. Please try again.':
      'आपका नाम सहेजा नहीं जा सका। कृपया पुनः प्रयास करें।',
  'How healthy is my crop right now?': 'मेरी फसल अभी कितनी स्वस्थ है?',
  'AI-powered crop intelligence.': 'AI-संचालित फसल बुद्धिमत्ता।',
  'AgriSentry combines all of this before recommending action.':
      'AgriSentry कार्रवाई सुझाने से पहले यह सब जोड़ता है।',
  'Weather Intelligence': 'मौसम बुद्धिमत्ता',
  'Driven by': 'प्रभावित करने वाले कारक',
  'ESTIMATED RISK': 'अनुमानित जोखिम',
  'ESTIMATED FUTURE RISK': 'अनुमानित भविष्य जोखिम',
  'CURRENT ENVIRONMENTAL RISK': 'वर्तमान पर्यावरणीय जोखिम',
  'DEMO MODEL - rule-based demo estimate, not a trained model':
      'डेमो मॉडल - नियम-आधारित डेमो अनुमान, प्रशिक्षित मॉडल नहीं',
  'demo_rules_v1: deterministic demo estimate for the selected crop':
      'demo_rules_v1: चयनित फसल के लिए निश्चित डेमो अनुमान',
  'TensorFlow Lite model not bundled yet - awaiting trained model export':
      'TensorFlow Lite मॉडल अभी शामिल नहीं है - प्रशिक्षित मॉडल निर्यात की प्रतीक्षा',
  'No .tflite model is bundled with this build.':
      'इस बिल्ड में कोई .tflite मॉडल शामिल नहीं है।',
  'TFLite model required for true inference.':
      'वास्तविक अनुमान के लिए TFLite मॉडल आवश्यक है।',
  'Backend unavailable': 'बैकएंड उपलब्ध नहीं',
  'Check that the backend is running and try again.':
      'बैकएंड चल रहा है या नहीं जांचें और पुनः प्रयास करें।',
  'The analysis service is unavailable. Check your connection and try again.':
      'विश्लेषण सेवा उपलब्ध नहीं है। अपना कनेक्शन जांचें और पुनः प्रयास करें।',
  'No crop analysis is available yet.':
      'अभी तक कोई फसल विश्लेषण उपलब्ध नहीं है।',
  'No risk assessment is available yet.':
      'अभी तक कोई जोखिम आकलन उपलब्ध नहीं है।',
  'No reading': 'कोई रीडिंग नहीं',
  'Sensor feed is simulated': 'सेंसर फीड सिम्युलेटेड है',
  'Device status is active. Simulated sensor feed is connected.':
      'डिवाइस स्थिति सक्रिय है। सिम्युलेटेड सेंसर फीड जुड़ा है।',
  'ESP32 live readings are not confirmed. Values are development or fallback data.':
      'ESP32 लाइव रीडिंग पुष्ट नहीं हैं। मान विकास या फॉलबैक डेटा हैं।',
  'When the real ESP32 kit is connected, this screen shows LIVE ESP32 data with no app changes. The device must send readings to your PC\'s LAN IP (e.g. http://192.168.1.20:8000) - never localhost.':
      'जब वास्तविक ESP32 किट जुड़ेगी, यह स्क्रीन बिना ऐप बदलाव के LIVE ESP32 डेटा दिखाएगी। डिवाइस को आपके PC के LAN IP (जैसे http://192.168.1.20:8000) पर रीडिंग भेजनी होंगी - localhost कभी नहीं।',

  // ----- history local detail -----
  'Leaf photo': 'पत्ती की तस्वीर',
  'Pending': 'लंबित',
};

/// Fixed UI chrome + complete one-piece strings (exact matches).
const Map<String, String> _te = {
  // ----- result screen -----
  'Leaf Analysis': 'ఆకు విశ్లేషణ',
  'SIMULATED DATA - development data, not live sensors':
      'సిమ్యులేటెడ్ డేటా - అభివృద్ధి డేటా, నిజమైన సెన్సార్ కాదు',
  'Backend unreachable - SIMULATED result shown':
      'బ్యాకెండ్ అందుబాటులో లేదు - సిమ్యులేటెడ్ ఫలితం చూపబడింది',
  'DEVELOPMENT MODEL - demo disease result, not a trained model':
      'డెవలప్‌మెంట్ మోడల్ - డెమో ఫలితం, శిక్షణ పొందిన మోడల్ కాదు',
  'Current Risk': 'ప్రస్తుత ప్రమాదం',
  'Future Risk (48h)': 'భవిష్యత్ ప్రమాదం (48 గం.)',
  'RISK OUTLOOK': 'ప్రమాద అవలోకనం',
  'Crop: Tomato': 'పంట: టమాటా',
  'WHY?': 'ఎందుకు?',
  'WHAT SHOULD I DO?': 'నేను ఏమి చేయాలి?',
  'This is an estimate based on current conditions and weather trends, not a guaranteed forecast.':
      'ఇది ప్రస్తుత పరిస్థితులు మరియు వాతావరణ ధోరణుల ఆధారంగా అంచనా మాత్రమే - హామీ కాదు.',

  // ----- why screen -----
  'Why?': 'ఎందుకు?',
  'WHY THIS RISK?': 'ఈ ప్రమాదం ఎందుకు?',
  'Contributing Factors': 'ప్రభావ కారణాలు',
  'The Details': 'వివరాలు',
  'What we saw': 'మేము ఏమి చూశాము',
  'Environment': 'పరిసరాలు',
  'Weather': 'వాతావరణం',
  'History': 'చరిత్ర',
  'Possible alternatives': 'సాధ్యమైన ప్రత్యామ్నాయాలు',
  'Observed': 'గమనించినవి',
  'Inferred': 'అంచనా',
  'Supported by context': 'సందర్భ ఆధారాలు',
  'Environmental connection': 'పర్యావరణ సంబంధం',
  'Uncertain': 'నిశ్చయంగా చెప్పలేనివి',
  'Why this risk': 'ఈ ప్రమాదం ఎందుకు',
  'Risk': 'ప్రమాదం',
  'Severity assessment': 'తీవ్రత అంచనా',
  'Treatment and management': 'చికిత్స మరియు నిర్వహణ',
  'What to do now': 'ఇప్పుడు ఏమి చేయాలి',
  'Next 3-7 days': 'తదుపరి 3-7 రోజులు',
  'Prevention': 'నివారణ',
  'What to monitor': 'ఏమి గమనించాలి',
  'When to contact an expert': 'నిపుణుడిని ఎప్పుడు సంప్రదించాలి',
  'Diagnostic limits': 'నిర్ధారణ పరిమితులు',
  'confidence': 'నమ్మకం',
  'Risk score': 'ప్రమాద స్కోరు',
  'Why': 'ఎందుకు',
  'AI Explanation': 'AI వివరణ',
  'What to do': 'ఏమి చేయాలి',
  'Loading past scans...': 'గత స్కాన్‌లను లోడ్ చేస్తున్నాం...',
  'No scans yet': 'ఇంకా స్కాన్‌లు లేవు',
  'Scan your first leaf to start building history.':
      'చరిత్రను ప్రారంభించడానికి మీ మొదటి ఆకును స్కాన్ చేయండి.',
  'AI Confidence': 'AI నమ్మకం',
  'Home': 'హోమ్',
  'Device': 'పరికరం',
  'Sample alerts - driven by the live risk engine in backend mode':
      'నమూనా హెచ్చరికలు - బ్యాకెండ్‌లోని లైవ్ రిస్క్ ఇంజిన్ ఆధారంగా',
  'ACTIVE': 'సక్రియం',
  'OK': 'సరే',
  'When the real ESP32 kit is connected, this screen shows LIVE ESP32 data with no app changes. The device must send readings to your PC\'s LAN IP (e.g. http://192.168.1.20:8000) - never localhost.':
      'నిజమైన ESP32 కిట్ కనెక్ట్ చేసినప్పుడు ఈ స్క్రీన్ LIVE ESP32 డేటాను చూపిస్తుంది. పరికరం మీ PC LAN IP కి రీడింగ్‌లను పంపాలి (ఉదా. http://192.168.1.20:8000) - localhost కాదు.',

  // ----- recommendations screen -----
  'What To Do?': 'ఏమి చేయాలి?',
  'DO NOW': 'వెంటనే చేయండి',
  'MANAGE': 'నిర్వహించండి',
  'PREVENT': 'నివారించండి',
  'MONITOR': 'గమనించండి',
  'WATER': 'నీటి నిర్వహణ',
  'ENVIRONMENT': 'పరిసరాలు',
  'These are AI-generated preventive suggestions. They do not replace professional agricultural advice - consult your local agricultural officer before applying any treatment.':
      'ఇవి AI సూచించిన నివారణ చర్యలు మాత్రమే. ఇవి నిపుణుల సలహాకు ప్రత్యామ్నాయం కాదు - ఏదైనా చర్య తీసుకునే ముందు మీ ప్రాంతీయ వ్యవసాయ అధికారిని సంప్రదించండి.',

  // ----- risk factor sentences (single-sentence ones) -----
  'Soil is very wet': 'నేల చాలా తడిగా ఉంది',
  'Soil is dry; the plant is under stress': 'నేల పొడిగా ఉంది; మొక్క ఒత్తిడిలో ఉంది',
  'Leaves stayed wet for a long time': 'ఆకులు ఎక్కువ సేపు తడిగా ఉన్నాయి',
  'Rain was recorded recently': 'ఇటీవల వర్షం నమోదైంది',
  'The weather outlook is getting worse (more rain expected)':
      'వాతావరణం దిగజారుతోంది (మరిన్ని వర్షాలు అంచనా)',
  'A recent scan already showed high risk':
      'ఇటీవలి స్కాన్ ఇప్పటికే అధిక ప్రమాదాన్ని చూపింది',
  'Conditions look normal right now': 'ప్రస్తుత పరిస్థితులు సాధారణంగా ఉన్నాయి',

  // ----- explanation sentences -----
  'The leaf looks healthy': 'ఆకు ఆరోగ్యంగా కనిపిస్తోంది',
  'These wet, warm conditions help disease spread':
      'ఈ తడి, వెచ్చని పరిస్థితులు వ్యాధి వ్యాప్తికి సహాయపడతాయి',
  'These warm, wet conditions help disease spread':
      'ఈ వెచ్చని, తడి పరిస్థితులు వ్యాధి వ్యాప్తికి సహాయపడతాయి',
  'These conditions are within a normal range':
      'ఈ పరిస్థితులు సాధారణ పరిధిలో ఉన్నాయి',
  'Rain is expected soon, which can increase the risk':
      'త్వరలో వర్షం అంచనా వేయబడింది, ఇది ప్రమాదాన్ని పెంచుతుంది',
  'The weather is expected to improve': 'వాతావరణం మెరుగుపడుతుందని అంచనా',
  'The weather is expected to stay stable': 'వాతావరణం స్థిరంగా ఉంటుందని అంచనా',
  'The problem may be growing': 'సమస్య పెరుగుతుందేమో',

  // ----- recommendation titles -----
  'Inspect the affected leaves': 'ప్రభావిత ఆకులను పరిశీలించండి',
  'Remove badly infected leaves': 'బాగా వ్యాధిగ్రస్తమైన ఆకులను తొలగించండి',
  'Apply a suitable fungicide': 'తగిన ఫంగిసైడ్ వాడండి',
  'Mulch around the plants': 'మొక్కల చుట్టూ మల్చింగ్ చేయండి',
  'Improve air circulation': 'గాలి ప్రసరణ మెరుగుపరచండి',
  'Improve airflow': 'గాలి ప్రసరణ మెరుగుపరచండి',
  'Maintain good airflow': 'గాలి ప్రసరణ సరిగా ఉంచండి',
  'Rotate crops next season': 'వచ్చే సీజన్‌లో పంటలు మార్చి పండించండి',
  'Water at the base, not the leaves': 'ఆకులపై కాకుండా మొక్క బుడగ వద్ద నీరు పోయండి',
  'Act immediately - Late Blight spreads fast':
      'వెంటనే చర్య తీసుకోండి - లేట్ బ్లైట్ వేగంగా వ్యాపిస్తుంది',
  'Apply recommended fungicide urgently': 'సిఫార్సు చేసిన ఫంగిసైడ్‌ను వెంటనే వాడండి',
  'Avoid working in the field when wet': 'తడి ఉన్నప్పుడు పొలంలో పని చేయవద్దు',
  'Keep leaves dry': 'ఆకులను పొడిగా ఉంచండి',
  'Remove infected leaves': 'వ్యాధిగ్రస్త ఆకులను తొలగించండి',
  'Use copper-based spray': 'కాపర్ ఆధారిత స్ప్రే వాడండి',
  'Disinfect tools and hands': 'పనిముట్లు, చేతులను శుభ్రంగా ఉంచండి',
  'Avoid overhead irrigation': 'పైనుంచి నీరు చల్లడం మానేయండి',
  'Water early in the morning': 'ఉదయాన్నే నీరు పోయండి',
  'Monitor the crop closely': 'పంటను నిశితంగా గమనించండి',
  'Keep the field clean': 'పొలాన్ని శుభ్రంగా ఉంచండి',
  'Keep monitoring': 'గమనిస్తూ ఉండండి',
  'Monitor every 2-3 days': 'ప్రతి 2-3 రోజులకు గమనించండి',
  'Monitor daily': 'రోజూ గమనించండి',
  'Keep up good practices': 'మంచి పద్ధతులను కొనసాగించండి',

  // ----- recommendation details (full strings) -----
  'Check lower, older leaves first - Early Blight usually starts there.':
      'ముందుగా కింది, పాత ఆకులను చూడండి - అర్లీ బ్లైట్ సాధారణంగా అక్కడే మొదలవుతుంది.',
  'Pick off heavily spotted leaves and destroy them. Do not compost them.':
      'బాగా మచ్చలున్న ఆకులను తీసి నాశనం చేయండి. వాటిని కంపోస్టులో వేయవద్దు.',
  'Use a copper-based or recommended fungicide from your local dealer, following the label. Confirm the choice with your agricultural officer.':
      'మీ ప్రాంతీయ డీలర్ దగ్గర లేబుల్ ప్రకారం కాపర్ ఆధారిత లేదా సిఫార్సు చేసిన ఫంగిసైడ్ తీసుకోండి. ఎంపికను మీ వ్యవసాయ అధికారితో ఖరారు చేసుకోండి.',
  'Use a copper-based or recommended fungicide, following the label. Confirm with your agricultural officer.':
      'లేబుల్ ప్రకారం కాపర్ ఆధారిత లేదా సిఫార్సు చేసిన ఫంగిసైడ్ వాడండి. మీ వ్యవసాయ అధికారితో ఖరారు చేసుకోండి.',
  'Mulching stops fungal spores in the soil from splashing onto leaves during rain.':
      'మల్చింగ్ వల్ల వర్షం సమయంలో నేలలోని ఫంగస్ బీజాలు చిమ్మి ఆకులపై పడకుండా ఉంటాయి.',
  'Space plants properly and remove weeds so leaves dry faster.':
      'మొక్కలకు సరైన దూరం ఉంచండి, కలుపు మొక్కలను తొలగించండి - ఆకులు త్వరగా ఆరిపోతాయి.',
  'Do not plant tomato or potato in the same spot next season.':
      'వచ్చే సీజన్‌లో అదే చోట టమాటా లేదా బంగాళదుంప పండించవద్దు.',
  'Use drip or base watering early in the day so leaves stay dry.':
      'ఆకులు తడిగా ఉండకుండా, డ్రిప్ ద్వారా లేదా బుడగ వద్ద ఉదయాన్నే నీరు పోయండి.',
  'Check the whole field today and remove infected plants and leaves.':
      'ఈ రోజే మొత్తం పొలం పరిశీలించి, వ్యాధిగ్రస్త మొక్కలు, ఆకులను తొలగించండి.',
  'Late Blight can destroy a crop within days in cool, wet weather. Consult your agricultural officer for the right product.':
      'చల్లని, తడి వాతావరణంలో లేట్ బ్లైట్ కొన్ని రోజుల్లోనే పంటను నాశనం చేస్తుంది. సరైన మందు కోసం మీ వ్యవసాయ అధికారిని సంప్రదించండి.',
  'The fungus spreads on wet clothes, tools and hands.':
      'తడి బట్టలు, పనిముట్లు, చేతుల ద్వారా ఫంగస్ వ్యాపిస్తుంది.',
  'Stop overhead watering until the outbreak is under control.':
      'వ్యాధి అదుపులోకి వచ్చే వరకు పైనుంచి నీరు చల్లడం ఆపండి.',
  'Prune spotted leaves with clean tools and dispose of them away from the field.':
      'శుభ్రమైన పనిముట్లతో మచ్చలున్న ఆకులను కత్తిరించి, పొలం దాటి దూరంగా పారవేయండి.',
  'Copper bactericides help limit spread. Confirm dosage with your dealer or officer.':
      'కాపర్ బ్యాక్టీరిసైడ్లు వ్యాప్తిని అరికడతాయి. మోతాదు కోసం మీ డీలర్ లేదా అధికారిని సంప్రదించండి.',
  'Bacteria spread through wounds and wet contact.':
      'గాయాలు, తడి సంపర్కం ద్వారా బ్యాక్టీరియా వ్యాపిస్తుంది.',
  'Splashing water spreads the bacteria leaf to leaf.':
      'నీరు చిమ్మడం వల్ల బ్యాక్టీరియా ఆకు నుంచి ఆకుకు వ్యాపిస్తుంది.',
  'This lets leaves dry quickly during the day.':
      'దీని వల్ల ఆకులు పగటిపూట త్వరగా ఆరిపోతాయి.',
  'Check leaves every 2-3 days for spreading spots.':
      'ప్రతి 2-3 రోజులకు ఆకులపై మచ్చలు వ్యాపిస్తున్నాయేమో చూడండి.',
  'Remove plant waste and weeds around the crop.':
      'పంట చుట్టూ మొక్కల వ్యర్థాలు, కలుపు మొక్కలను తొలగించండి.',
  'Scan a leaf once a week and watch the risk on the dashboard.':
      'వారానికి ఒకసారి ఆకును స్కాన్ చేసి, డాష్‌బోర్డ్‌లో ప్రమాద స్థాయిని చూస్తూ ఉండండి.',
  'Scan again soon - conditions could get worse.':
      'త్వరలో మళ్లీ స్కాన్ చేయండి - పరిస్థితి దిగజారే అవకాశం ఉంది.',
  'Check the crop every day and follow the actions above.':
      'రోజూ పంటను పరిశీలించి, పైన సూచించిన చర్యలు పాటించండి.',
  'Healthy crop! Maintain spacing, clean field and steady watering.':
      'పంట ఆరోగ్యంగా ఉంది! సరైన దూరం, శుభ్రమైన పొలం, క్రమం తప్పకుండా నీరు ఉంచండి.',
  'Space plants and remove weeds so leaves dry quickly after rain or watering.':
      'మొక్కలకు దూరం ఉంచి కలుపు తీయండి - వర్షం లేదా నీరు పోయిన తర్వాత ఆకులు త్వరగా ఆరిపోతాయి.',
  'Space plants and remove weeds so leaves dry quickly after rain.':
      'మొక్కలకు దూరం ఉంచి కలుపు తీయండి - వర్షం తర్వాత ఆకులు త్వరగా ఆరిపోతాయి.',
  'Farmer': 'రైతు',
  'Disease': 'వ్యాధి',
  'Health': 'ఆరోగ్యం',
  'Rainfall': 'వర్షపాతం',
  'Right Now': 'ప్రస్తుతం',
  'Farm warning': 'పంట హెచ్చరిక',
  'Reading sensors...': 'సెన్సార్లను చదువుతున్నాం...',
  'Last updated:': 'చివరిగా నవీకరించినది:',
  'Temperature (recent readings)': 'ఉష్ణోగ్రత (ఇటీవలి రీడింగ్‌లు)',
  'Humidity (recent readings)': 'తేమ (ఇటీవలి రీడింగ్‌లు)',
  'Soil Moisture (recent readings)': 'నేల తేమ (ఇటీవలి రీడింగ్‌లు)',
  'DEVICE STATUS': 'పరికరం స్థితి',
  'Scanning leaf...': 'ఆకును స్కాన్ చేస్తున్నాం...',
  'Checking visible symptoms...': 'కనిపించే లక్షణాలను పరిశీలిస్తున్నాం...',
  'Analyzing crop health...': 'పంట ఆరోగ్యాన్ని విశ్లేషిస్తున్నాం...',
  'Combining environmental conditions...':
      'పర్యావరణ పరిస్థితులను కలుపుతున్నాం...',
  'Preparing your crop health report...':
      'మీ పంట ఆరోగ్య నివేదికను సిద్ధం చేస్తున్నాం...',
  'Our AI is looking at your leaf and your field conditions.':
      'మా AI మీ ఆకు మరియు పొల పరిస్థితులను పరిశీలిస్తోంది.',
  'NOW': 'ఇప్పుడు',
  'SEE  ·  UNDERSTAND  ·  PREDICT  ·  PREVENT':
      'చూడండి  ·  అర్థం చేసుకోండి  ·  అంచనా వేయండి  ·  నివారించండి',

  // ----- home screen -----
  'Good morning': 'శుభోదయం',
  'Good afternoon': 'శుభ మధ్యాహ్నం',
  'Good evening': 'శుభ సంధ్య',
  'Your Tomato Field': 'మీ టమాటా పొలం',
  'Loading your farm...': 'మీ పంటను లోడ్ చేస్తున్నాం...',
  'CROP HEALTH': 'పంట ఆరోగ్యం',
  'GOOD': 'మంచిది',
  'FAIR': 'సరిపోతుంది',
  'AT RISK': 'ప్రమాదంలో',
  'Environmental Conditions': 'పర్యావరణ పరిస్థితులు',
  'Details': 'వివరాలు',
  'Temperature': 'ఉష్ణోగ్రత',
  'Humidity': 'తేమ',
  'Soil Moisture': 'నేల తేమ',
  'Light': 'కాంతి',
  'AI Insight': 'AI అభిప్రాయం',
  'Detailed AI Analysis': 'వివరణాత్మక AI విశ్లేషణ',
  'Main reasons': 'ప్రధాన కారణాలు',
  'No crop analysis is available yet.': 'ఇంకా పంట విశ్లేషణ అందుబాటులో లేదు.',
  'Device status is active. Simulated sensor feed is connected.':
      'పరికరం స్థితి సక్రియంగా ఉంది. సిమ్యులేటెడ్ సెన్సార్ ఫీడ్ కనెక్ట్ అయింది.',
  'Take a clear leaf photo in daylight, then analyze the leaf.':
      'పగటి వెలుతురులో స్పష్టమైన ఆకు ఫోటో తీసి, ఆ ఆకును విశ్లేషించండి.',
  'SCAN LEAF': 'ఆకు స్కాన్ చేయండి',
  'Full forecast': 'సంపూర్ణ సూచన',
  'Source:': 'మూలం:',
  'Recent Alert': 'ఇటీవలి హెచ్చరిక',
  'All alerts': 'అన్ని హెచ్చరికలు',
  'Recent scans': 'ఇటీవలి స్కాన్‌లు',
  'View all': 'అన్నీ చూడండి',
  'Early Blight detected and conditions favor spread.': 'అర్లీ బ్లైట్ కనుగొనబడింది మరియు పరిస్థితులు వ్యాప్తికి అనుకూలం.',
  'High disease risk': 'వ్యాధి ప్రమాదం ఎక్కువగా ఉంది',
  'High humidity': 'తేమ ఎక్కువగా ఉంది',
  'Rain expected': 'వర్షం అంచనా',
  'Humidity stayed above 80% for hours. Watch for leaf diseases.':
      'తేమ గంటల పాటు 80% కంటే ఎక్కువగా ఉంది. ఆకు వ్యాధుల కోసం గమనించండి.',
  'Rain in the next 24h may increase disease risk.':
      'తదుపరి 24 గంటల్లో వర్షం వ్యాధి ప్రమాదాన్ని పెంచవచ్చు.',
  'Temperature is 27 C, humidity 82%. These warm, wet conditions help disease spread.':
      'ఉష్ణోగ్రత 27°C, తేమ 82%. ఈ వెచ్చని, తడి పరిస్థితులు వ్యాధి వ్యాప్తికి సహాయపడతాయి.',
  'Your crop currently looks healthy, but humidity is increasing. Scan a leaf soon to be sure.':
      'మీ పంట ప్రస్తుతం ఆరోగ్యంగా కనిపిస్తోంది, కానీ తేమ పెరుగుతోంది. నిర్ధారించుకోవడానికి త్వరలో ఆకును స్కాన్ చేయండి.',
  'Your crop is at high risk (78/100). Early Blight was detected and humid, warm weather helps it spread.':
      'మీ పంటకు అధిక ప్రమాదం ఉంది (78/100). అర్లీ బ్లైట్ గుర్తించబడింది మరియు తేమతో కూడిన వెచ్చని వాతావరణం వ్యాప్తికి సహాయపడుతుంది.',

  // ----- common.dart widgets -----
  'OFFLINE - showing saved simulated data': 'ఆఫ్‌లైన్ - సేవ్ చేసిన సిమ్యులేటెడ్ డేటా చూపిస్తున్నాం',
  'Loading...': 'లోడ్ చేస్తున్నాం...',
  'Stop': 'ఆపండి',
  'Read aloud': 'చదువు',
  'No alerts': 'హెచ్చరికలు లేవు',
  'Everything looks fine on your farm right now.': 'ప్రస్తుతం మీ పంటపై ప్రతిదీ సరిగా ఉంది.',
  'Check that the backend is running and try again.': 'బ్యాకెండ్ నడుస్తున్నదని తనిఖీ చేసి మళ్లీ ప్రయత్నించండి.',
  'Try again': 'మళ్లీ ప్రయత్నించండి',

  // ----- alerts screen -----
  'Alerts': 'హెచ్చరికలు',

  // ----- sensors screen -----
  'Device:': 'పరికరం:',
  'Rain': 'వర్షం',
  'Device Status': 'పరికరం స్థితి',
  'Connection': 'కనెక్షన్',
  'Status': 'స్థితి',
  'Simulated feed active': 'సిమ్యులేటెడ్ ఫీడ్ సక్రియంగా ఉంది',
  'Data source': 'డేటా మూలం',
  'SIMULATED (not live ESP32)': 'సిమ్యులేటెడ్ (లైవ్ ESP32 కాదు)',
  'Backend': 'బ్యాకెండ్',
  'Sensors': 'సెన్సార్లు',
  'Temperature / Humidity': 'ఉష్ణోగ్రత / తేమ',
  'Soil moisture': 'నేల తేమ',
  'Light (LDR)': 'కాంతి (LDR)',

  // ----- weather screen -----
  'Rain expected soon. Increased humidity may increase disease risk. Check that leaves can dry quickly and consider scanning a leaf after the rain.':
      'త్వరలో వర్షం అంచనా. తేమ పెరిగితే వ్యాధి ప్రమాదం పెరుగుతుంది. ఆకులు త్వరగా ఆరిపోయే విధంగా ఉన్నాయో చూడండి మరియు వర్షం తర్వాత ఆకు స్కాన్ చేయండి.',
  'Weather outlook is stable or improving. Keep up normal monitoring.': 'వాతావరణం స్థిరంగా లేదా మెరుగుపడుతోంది. సాధారణ పర్యవేక్షణ కొనసాగించండి.',
  'Risk intelligence': 'ప్రమాద సమాచారం',
  'VIEW RISK': 'ప్రమాదాన్ని చూడండి',
  'Scan crop': 'పంటను స్కాన్ చేయండి',
  'No risk assessment yet': 'ఇంకా ప్రమాద అంచనా లేదు',
  'Scan a leaf to combine visual symptoms with field conditions.':
      'ఆకు లక్షణాలను పొలం పరిస్థితులతో కలపడానికి ఆకును స్కాన్ చేయండి.',
  'Why this risk level?': 'ఈ ప్రమాద స్థాయి ఎందుకు?',
  'Estimated future risk': 'అంచనా భవిష్యత్ ప్రమాదం',
  'What to consider next': 'తర్వాత ఏమి గమనించాలి',
  'Review the detected symptoms': 'గుర్తించిన లక్షణాలను పరిశీలించండి',
  'Review recommendations': 'సిఫార్సులను పరిశీలించండి',
  'IMAGE QUALITY LOOKS GOOD': 'చిత్ర నాణ్యత బాగుంది',
  'IMAGE QUALITY NEEDS IMPROVEMENT': 'చిత్ర నాణ్యతను మెరుగుపరచండి',
  'LIVE SENSOR DATA': 'లైవ్ సెన్సార్ డేటా',
  'Backend reachable': 'బ్యాకెండ్ అందుబాటులో ఉంది',
  'Live connection not confirmed': 'లైవ్ కనెక్షన్ నిర్ధారించబడలేదు',
  'AVAILABLE': 'అందుబాటులో ఉంది',
  'NO DATA': 'డేటా లేదు',

  // ----- multi-crop + plant identification (audit sections 3, 4) -----
  'Your Crop': 'మీ పంట',
  'Add or scan a crop to get started': 'ప్రారంభించడానికి పంటను జోడించండి లేదా స్కాన్ చేయండి',
  'Your Rice Field': 'మీ వరి పొలం',
  'Your Cotton Field': 'మీ పత్తి పొలం',
  'Your Chilli Field': 'మీ మిర్చి పొలం',
  'Your Maize Field': 'మీ మొక్కజొన్న పొలం',
  'Your crop': 'మీ పంట',
  'Select your crop above so the AI uses the right knowledge.':
      'సరైన సమాచారం కోసం AI ఉపయోగించేలా పైన మీ పంటను ఎంచుకోండి.',
  'Plant': 'మొక్క',
  'Selected by you': 'మీరు ఎంచుకున్నది',
  'What to look for': 'ఏమి చూడాలి',
  'Monitor': 'పరిశీలించండి',
  'View Technical Details': 'సాంకేతిక వివరాలు చూడండి',
  'Disease model status': 'వ్యాధి మోడల్ స్థితి',
  'Risk engine': 'ప్రమాద ఇంజన్',
  'Prediction model': 'అంచనా మోడల్',
  'VIEW FULL EXPLANATION': 'పూర్తి వివరణ చూడండి',
  'No visible disease': 'వ్యాధి కనిపించడం లేదు',
  'How this works: AgriSentry AI combined the leaf image, weather, sensor readings and your recent scan history to estimate this risk using transparent, documented rules.':
      'ఇది ఎలా పనిచేస్తుంది: AgriSentry AI ఆకు చిత్రం, వాతావరణం, సెన్సార్ రీడింగ్‌లు మరియు ఇటీవలి స్కాన్ చరిత్రను పారదర్శక, డాక్యుమెంట్ చేసిన నియమాలతో కలిపి ఈ ప్రమాదాన్ని అంచనా వేసింది.',
  'AI guidance supports - but does not replace - your local agricultural experts, especially when the situation is severe or uncertain.':
      'AI సలహా మీ స్థానిక వ్యవసాయ నిపుణులకు తోడ్పాటు - ప్రత్యామ్నాయం కాదు, ముఖ్యంగా పరిస్థితి తీవ్రంగా లేదా అనిశ్చితంగా ఉన్నప్పుడు.',
  'Select your crop': 'మీ పంటను ఎంచుకోండి',

  // ----- sync + offline (audit sections 5, 16) -----
  'Synchronization': 'సమకాలీకరణ',
  'Sync now': 'ఇప్పుడే సింక్ చేయండి',
  'Last sync': 'చివరి సింక్',
  'Synced': 'సింక్ అయింది',
  'Sync pending': 'సింక్ మిగిలిపోయింది',
  'Syncing...': 'సింక్ అవుతోంది...',
  'Offline - saved on device': 'ఆఫ్‌లైన్ - పరికరంలో సురక్షితం',
  'All analyses are saved and synced.': 'అన్ని విశ్లేషణలు సేవ్ చేయబడి సింక్ అయ్యాయి.',
  'analyses waiting to sync': 'విశ్లేషణలు సింక్ కోసం వేచి ఉన్నాయి',
  'saved safely on this device. Will sync automatically when internet is available.':
      'ఈ పరికరంలో సురక్షితంగా ఉన్నాయి. ఇంటర్నెట్ వచ్చినప్పుడు స్వయంచాలకంగా సింక్ అవుతాయి.',
  'Offline-first: analyses are always saved on this device first and synced when internet returns.':
      'ఆఫ్‌లైన్-మొదటి: విశ్లేషణలు ఎప్పుడూ మొదట ఈ పరికరంలో సేవ్ అవుతాయి, ఇంటర్నెట్ తిరిగి వచ్చాక సింక్ అవుతాయి.',

  // ----- weather agricultural impact (audit section 17) -----
  'Agricultural Impact': 'వ్యవసాయ ప్రభావం',
  'Humidity is high': 'తేమ ఎక్కువగా ఉంది',
  'High humidity may increase fungal disease risk. Watch leaf condition and scan a leaf if spots appear.':
      'అధిక తేమ వల్ల ఫంగస్ వ్యాధి ప్రమాదం పెరిగే అవకాశం ఉంది. ఆకు స్థితిని గమనించండి, మచ్చలు కనిపిస్తే ఆకును స్కాన్ చేయండి.',
  'Weather feeds directly into the AgriSentry AI risk engine - a scan taken now combines these conditions with the leaf image.':
      'వాతావరణం నేరుగా AgriSentry AI ప్రమాద ఇంజన్‌లోకి వెళ్తుంది - ఇప్పుడు చేసే స్కాన్ ఈ పరిస్థితులను ఆకు చిత్రంతో కలుపుతుంది.',

  // ----- history local detail -----
  'Leaf photo': 'ఆకు ఫోటో',
  'Pending': 'పెండింగ్',

  // ----- scan screen -----
  'Scan Crop': 'పంటను స్కాన్ చేయండి',
  'No leaf photo yet': 'ఆకు చిత్రం ఇంకా లేదు',
  'Camera': 'కెమెరా',
  'Gallery': 'ఫోటో లైబ్రరీ',
  'For the best result:': 'ఉత్తమ ఫలితం కోసం:',
  '• Use daylight, not direct glare\n• Fill the frame with one leaf\n• Hold the phone steady\n• Include the spotted part of the leaf':
      '• ప్రత్యక్ష కాంతి కాకుండా పగటి వెలుతురు వాడండి\n• ఒక ఆకుతో ఫ్రేమ్‌ను నింపండి\n• ఫోన్‌ను స్థిరంగా పట్టుకోండి\n• మచ్చ ఉన్న ఆకుభాగాన్ని చేర్చండి',
  'TAKE A PHOTO FIRST': 'మొదట ఫోటో తీసుకోండి',
  'ANALYZE THIS LEAF': 'ఈ ఆకును విశ్లేషించండి',
  'RETAKE PHOTO': 'ఫోటో మళ్లీ తీసుకోండి',

  // ----- audit: knowledge base, actions and explanations -----
  'Scan a leaf to calculate risk from image + environment.':
      'చిత్రం + పర్యావరణం నుండి ప్రమాదాన్ని లెక్కించడానికి ఆకును స్కాన్ చేయండి.',
  'Scan a leaf weekly and watch the risk on the dashboard.':
      'వారానికి ఒకసారి ఆకును స్కాన్ చేసి డాష్‌బోర్డ్‌లో ప్రమాదాన్ని చూడండి.',
  'The photo file is empty or unreadable.': 'ఫోటో ఫైల్ ఖాళీగా ఉంది లేదా చదవలేము.',
  'The photo looks too dark. Use daylight, not shade.':
      'ఫోటో చాలా మసకంగా ఉంది. నీడ కాకుండా పగటి వెలుతురు వాడండి.',
  'The photo looks blurry. Hold the phone steady and retake it.':
      'ఫోటో మచ్చగా ఉంది. ఫోన్‌ను స్థిరంగా పట్టుకుని మళ్లీ తీయండి.',
  'No reliable disease detected': 'नम्मदगिन व्याधि गुर्तिंचबडलेदु',
  'Not selected yet': 'इంకా ఎంచుకోలేదు',
  'Waiting for scan': 'స్కాన్ కోసం వేచి ఉన్నాము',
  'Not analyzed': 'విశ్లేషించబడలేదు',
  'Legal': 'చట్టపరమైనవి',
  'Privacy Policy': 'గోపనీయతా విధానం',
  'Terms and Conditions': 'నిబంధనలు మరియు షరతులు',
  'This document is provided in English.': 'ఈ పత్రం ఆంగ్లంలో అందించబడింది.',
  'Sensor data unavailable': 'సెన్సర్ డేటా అందుబాటులో లేదు',
  'Weather data unavailable': 'వాతావరణ డేటా అందుబాటులో లేదు',
  'Backend unreachable - disease could not be determined from this image': 'బ్యాక్‌ఎండ్ అందుబాటులో లేదు - ఈ చిత్రం నుండి వ్యాధిని నిర్ధారించలేము',
  'Scan a leaf to get your first AI insight.': 'మీ మొదటి ఏఐ సమాచారం కోసం ఆకును స్కాన్ చేయండి.',
  'No live weather is available right now. Values are not simulated - pull down to retry.':
      'ప్రస్తుతం ప్రత్యక్ష వాతావరణ సమాచారం లేదు. విలువలు కృత్రిమంగా చూపబడవు - మళ్లీ ప్రయత్నించడానికి క్రిందికి లాగండి.',
  'Retry': 'మళ్లీ ప్రయత్నించండి',
  'No ESP32 sensor readings are available right now. Values are not simulated - check the device and pull down to retry.':
      'ప్రస్తుతం ESP32 సెన్సర్ రీడింగ్‌లు అందుబాటులో లేవు. విలువలు కృత్రిమంగా చూపబడవు - పరికరాన్ని తనిఖీ చేసి, మళ్లీ ప్రయత్నించడానికి క్రిందికి లాగండి.',
  'demo_rules_v1: no trained image model is bundled, so disease cannot be determined from this photo. Provide the backend API or bundle a TFLite model for real inference.':
      'demo_rules_v1: శిక్షణ పొందిన చిత్ర నమూనా చేర్చబడలేదు, కాబట్టి ఈ ఫోటో నుండి వ్యాధిని నిర్ధారించలేము. నిజమైన విశ్లేషణ కోసం బ్యాక్‌ఎండ్ API లేదా TFLite నమూనాను జోడించండి.',
  'The available image evidence is not strong enough to name a disease. Environmental conditions may affect future risk, but they do not prove a current disease.':
      'వ్యాధిని పేర్కొనడానికి చిత్రంలోని ఆధారాలు సరిపోని బలం కలిగి లేవు. పర్యావరణ పరిస్థితులు భవిష్యత్తు ప్రమాదాన్ని ప్రభావితం చేయవచ్చు, కానీ అవి ప్రస్తుత వ్యాధిని నిర్ధారించవు.',
  'The photo looks overexposed. Avoid direct glare.':
      'ఫోటోలో ఎక్కువ వెలుతురు ఉంది. నేరుగా మెరుపు నుండి దూరంగా ఉండండి.',
  'Too dark': 'చాలా మసకం',
  'Too bright': 'చాలా వెలుగు',
  'The leaf looks green and uniform with no spots or discoloration.':
      'ఆకు ఆకుపచ్చగా ఏకరీతిగా ఉంది, మచ్చలు లేదా రంగు మార్పు లేదు.',
  'The leaf shows signs of Early Blight. The AI is 91% sure of this.':
      'ఆకుపై అర్లీ బ్లైట్ లక్షణాలు కనిపిస్తున్నాయి. AI దీని గురించి 91% ఖచ్చితంగా ఉంది.',
  'Visual symptoms detected in the leaf image.': 'ఆకు చిత్రంలో లక్షణాలు గుర్తించబడ్డాయి.',
  'Dark brown spots with concentric rings, usually starting on lower, older leaves with yellowing around them.':
      'గాఢంగా ఉన్న గోధుమ మచ్చలు వరుస వలయాలతో, సాధారణంగా కింది పాత ఆకులపై ప్రారంభమై చుట్టూ పసుపు రంగు కలిగి ఉంటాయి.',
  'Small brown circular spots with lighter centers on leaves; severe spots merge and leaves drop early.':
      'ఆకులపై తేలికపాటి మధ్యభాగం కలిగిన చిన్న గోధుమ వృత్తాకార మచ్చలు; తీవ్రంగా ఉన్నప్పుడు మచ్చలు కలిసి ఆకులు ముందే రాలుతాయి.',
  'Pale yellowish spots on the upper leaf surface with olive-green fuzzy mold underneath, in humid still air.':
      'పై ఆకు ఉపరితలంపై పసుపు మచ్చలు, కింద ఆలివ్-ఆకుపచ్చ బొచ్చు బొప్పు - తేమతో కూడిన నిశ్చల గాలిలో కనిపిస్తాయి.',
  'Greasy, water-soaked patches with white fuzzy growth under the leaf; spreads extremely fast in cool wet weather.':
      'నూనెగింజల వంటి నీటితో తడిసిన మచ్చలు, ఆకు కింద తెల్ల బొప్పు; చల్లని తడి వాతావరణంలో చాలా వేగంగా వ్యాపిస్తుంది.',
  'Small, dark, angular water-soaked spots that may look greasy; leaves can turn yellow and drop.':
      'చిన్న, ముదురు, కోణాత్మక నీటితో తడిసిన మచ్చలు జిగురుగా కనిపించవచ్చు; ఆకులు పసుపు రంగులోకి మారి రాలుతాయి.',
  'Wavy-edged yellow to straw-colored lesions running along leaf margins or veins, often after heavy rain or wind.':
      'ఆకు అంచుల వెంట లేదా సిరల వెంట అలల వంటి అంచుల పసుపు-గడ్డి రంగు మచ్చలు, సాధారణంగా భారీ వర్షం లేదా గాలి తర్వాత.',
  'Diamond-shaped spots with grey centers and brown edges on leaves; nodes or panicles may turn brown and break.':
      'ఆకులపై వజ్రాకార మచ్చలు - బూడిద మధ్యభాగం, గోధుమ అంచులు; ముఖ్యాలు లేదా గెలలు గోధుమ రంగులోకి మారి విరుస్తాయి.',
  'Long, cigar-shaped grey-green to tan lesions running along the leaves, growing larger in humid weather.':
      'ఆకుల వెంట సిగార్ ఆకారపు బూడిద-ఆకుపచ్చ నుండి గోధుమ మచ్చలు, తేమతో కూడిన వాతావరణంలో పెద్దవవుతాయి.',
  'Young leaves curl and pucker, plants look stunted with shortened internodes.':
      'కొత్త ఆకులు మడతబడి కుంగిపోతాయి, మొక్కలు పొట్టిగా కనిపిస్తాయి.',
  'Small, raised, cinnamon-brown pustules scattered on both leaf surfaces that rub off like powder.':
      'రెండు ఆకు ఉపరితలాలపై చెల్లాచెదురుగా ఉండే చిన్న, ఎత్తైన దాల్చిన-గోధుమ బొబ్బలు పొడిలా రాస్తే తొలగిపోతాయి.',
  'Upward or downward curling of leaves with thickened veins; leaves look small, leathery and dark.':
      'మందమైన సిరలతో ఆకులు పైకి-కిందకి మడతబడటం; ఆకులు చిన్నవిగా, తోలు వంటివిగా, ముదురుగా కనిపిస్తాయి.',
  'Many small circular spots with dark borders and tiny black dots (fruiting bodies) in the center, on lower leaves first.':
      'ముదురు అంచులు, మధ్యలో చిన్న నల్ల బిందువులు కలిగిన అనేక చిన్న వృత్తాకార మచ్చలు, మొదట కింది ఆకులపై.',
  'Spread of spots to upper leaves': 'పై ఆకులకు మచ్చల వ్యాప్తి',
  'Number of new spots': 'కొత్త మచ్చల సంఖ్య',
  'Lesion size and count': 'మచ్చల పరిమాణం మరియు సంఖ్య',
  'Pustule density': 'బొబ్బల సాంద్రత',
  'New spots': 'కొత్త మచ్చలు',
  'New spots on young leaves': 'కొత్త ఆకులపై కొత్త మచ్చలు',
  'New spots or discoloration': 'కొత్త మచ్చలు లేదా రంగు మార్పు',
  'New water-soaked patches': 'కొత్త నీటితో తడిసిన మచ్చలు',
  'New curled leaves': 'కొత్త మడత బడిన ఆకులు',
  'New diamond-shaped spots': 'కొత్త వజ్రాకార మచ్చలు',
  'Yellowing leaf margins': 'ఆకు అంచుల పసుపు రంగు',
  'Leaf drop': 'ఆకులు రాలడం',
  'Leaf condition': 'ఆకు స్థితి',
  'Leaf wetness': 'ఆకు తడి',
  'Leaf Wetness': 'ఆకు తడి',
  'Leaves stayed wet for a long time.': 'ఆకులు ఎక్కువ సేపు తడిగా ఉన్నాయి.',
  'Under-leaf mold growth': 'ఆకు కింద బొప్పు',
  'High soil moisture': 'ఎక్కువ నేల తేమ',
  'Temperature and humidity': 'ఉష్ణోగ్రత మరియు తేమ',
  'Field water level': 'పొలంలో నీటి మట్టం',
  'Whitefly counts': 'తెల్ల ఈగల సంఖ్య',
  'Whitefly or thrips presence': 'తెల్ల ఈగలు లేదా థ్రిప్స్ ఉనికి',
  'Plant vigor': 'మొక్క శక్తి',
  'Air movement': 'గాలి ప్రసరణ',
  'Mark how many plants show lesions to track spread at the next check.':
      'తర్వాతి తనిఖీలో వ్యాప్తిని గమనించడానికి ఎన్ని మొక్కలపై మచ్చలు ఉన్నాయో నమోదు చేయండి.',
  'Scout several field spots': 'పొలంలో అనేక చోట్ల తనిఖీ చేయండి',
  'Inspect the field edges': 'పొలం అంచులను తనిఖీ చేయండి',
  'Check the lower canopy': 'కింది ఆకులను తనిఖీ చేయండి',
  'Regular monitoring': 'నిత్య పరిశీలన',
  'Inspect for whiteflies and thrips': 'తెల్ల ఈగలు, థ్రిప్స్ కోసం తనిఖీ చేయండి',
  'Check for whitefly': 'తెల్ల ఈగల కోసం తనిఖీ చేయండి',
  'Water the crop': 'పంటకు నీరు పెట్టండి',
  'Reduce watering for now': 'ప్రస్తుతానికి నీరు తగ్గించండి',
  'Drain standing water briefly': 'నిలిచిన నీటిని కొద్దిసేపు తీసేయండి',
  'Manage water carefully': 'నీటిని జాగ్రత్తగా నిర్వహించండి',
  'Remove spotted leaves': 'మచ్చలున్న ఆకులను తీసేయండి',
  'Remove heavily affected leaves': 'ఎక్కువగా ప్రభావితమైన ఆకులను తీసేయండి',
  'Remove infected lower leaves': 'కింది వ్యాధిగ్రస్త ఆకులను తీసేయండి',
  'Remove visibly infected plants': 'కనిపించే వ్యాధిగ్రస్త మొక్కలను తీసేయండి',
  'Remove and destroy moldy leaves. Do not leave them in the field.':
      'బొప్పు పడిన ఆకులను తీసి నాశనం చేయండి. పొలంలో వదిలేయవద్దు.',
  'Remove and destroy badly curled plants': 'బాగా మడత బడిన మొక్కలను తీసి నాశనం చేయండి',
  'Remove severely curled plants': 'బాగా మడత బడిన మొక్కలను తీసేయండి',
  'Remove infected plants so whiteflies cannot spread the virus onward.':
      'తెల్ల ఈగలు వైరస్‌ను మరింత వ్యాప్తి చేయకుండా వ్యాధిగ్రస్త మొక్కలను తీసేయండి.',
  'Remove volunteer hosts': 'తామరాగా పెరిగిన మొక్కలను తీసేయండి',
  'Prune affected leaves with clean tools and dispose of them away from the field.':
      'శుభ్రమైన పనిముట్లతో ప్రభావిత ఆకులను కత్తిరించి పొలం నుండి దూరంగా నాశనం చేయండి.',
  'Destroy badly infected plants to protect healthy neighbors.':
      'ఆరోగ్యకరమైన మొక్కలను రక్షించడానికి బాగా వ్యాధిగ్రస్త మొక్కలను నాశనం చేయండి.',
  'Rotate crops': 'పంట మార్పిడి చేయండి',
  'Choose tolerant varieties next season': 'తర్వాతి సీజన్‌లో నిరోధక రకాలను ఎంచుకోండి',
  'Use healthy seedlings': 'ఆరోగ్యకరమైన మొక్కలను వాడండి',
  'Start with certified, disease-free nursery stock when available.':
      'అందుబాటులో ఉంటే ధృవీకరించిన, వ్యాధి లేని నర్సరీ మొక్కలతో ప్రారంభించండి.',
  'Ensure good field ventilation': 'పొలంలో గాలి ప్రసరణ సరిగా ఉంచండి',
  'Ensure ventilation': 'గాలి ప్రసరణ చూసుకోండి',
  'Improve airflow in the canopy': 'పంటలోపల గాలి ప్రసరణ మెరుగుపరచండి',
  'Open up dense foliage and improve ventilation - Leaf Mold thrives in still, humid air.':
      'దట్టమైన ఆకులను విప్పి గాలి ప్రసరణ మెరుగుపరచండి - లీఫ్ మోల్డ్ నిశ్చల, తేమ గాలిలో వేగంగా వ్యాపిస్తుంది.',
  'Reduce humidity inside the crop': 'పంటలోపల తేమ తగ్గించండి',
  'Avoid overhead watering': 'ఆకులపై నీరు చల్లడం మానేయండి',
  'Avoid overhead watering until the outbreak is under control.':
      'వ్యాధి అదుపులోకి వచ్చే వరకు ఆకులపై నీరు చల్లడం మానేయండి.',
  'Avoid excess nitrogen fertilizer': 'అవసరం కంటే ఎక్కువ నత్రజని ఎరువు వాడకండి',
  'Avoid heavy nitrogen stress': 'అధిక నత్రజని ఒత్తిడిని తప్పించుకోండి',
  'Avoid wounding plants': 'మొక్కలకు గాయాలు కలిగించకండి',
  'Disinfect tools and hands between plants.': 'మొక్కల మధ్య పనిముట్లు, చేతులను క్రిమిరహితం చేయండి.',
  'Apply a suitable bactericide': 'తగిన బాక్టీరిసైడ్ చల్లండి',
  'Yellow sticky traps and clean field edges reduce whitefly numbers. Confirm treatments locally.':
      'పసుపు బంధాలు మరియు శుభ్రమైన పొలం అంచులు తెల్ల ఈగలను తగ్గిస్తాయి. చికిత్సలను స్థానికంగా ఖరారు చేసుకోండి.',
  'Sticky traps and regular monitoring keep vectors low. Confirm treatments locally.':
      'బంధాలు మరియు నిత్య పరిశీలన వాహక కీటకాలను తక్కువగా ఉంచుతాయి. చికిత్సలను స్థానికంగా ఖరారు చేసుకోండి.',
  'Control whitefly pressure': 'తెల్ల ఈగల ఒత్తిడిని నియంత్రించండి',
  'Manage sucking pests early': 'పీల్చు పురుగులను ముందుగానే నియంత్రించండి',
  'Old crop residue and weeds harbor whiteflies between seasons.':
      'పాత పంట అవశేషాలు, కలుపు మొక్కలు సీజన్ల మధ్య తెల్ల ఈగలకు ఆశ్రయం ఇస్తాయి.',
  'Manage field residue': 'పొలం అవశేషాలను నిర్వహించండి',
  'Infected residue carries rust to the next crop.':
      'వ్యాధిగ్రస్త అవశేషాలు తర్వాతి పంటకు రస్ట్‌ను తీసుకెళ్తాయి.',
  'Maize-after-maize fields build up spores in the residue.':
      'వరుసగా మొక్కజొన్న పండించే పొలాల్లో అవశేషాల్లో బీజాంశం పేరుకుపోతుంది.',
  'Rust-tolerant hybrids are the most durable control.':
      'రస్ట్ నిరోధక సంకర రకాలే అత్యంత మన్నికైన నియంత్రణ.',
  'Rust builds quickly - count pustules on a few plants across the field.':
      'రస్ట్ వేగంగా పెరుగుతుంది - పొలమంతా కొన్ని మొక్కలపై బొబ్బలను లెక్కించండి.',
  'Balanced fertilization': 'సమతుల్య ఎరువులు',
  'Balanced plant density reduces humid, still air inside the canopy.':
      'సమతుల్య మొక్కల సాంద్రత పంటలోపల తేమ, నిశ్చల గాలిని తగ్గిస్తుంది.',
  'Wider spacing between seedlings reduces humid, still air.':
      'మొక్కల మధ్య ఎక్కువ దూరం తేమ, నిశ్చల గాలిని తగ్గిస్తుంది.',
  'Wider spacing helps leaves dry quickly after rain or watering.':
      'ఎక్కువ దూరంతో వర్షం లేదా నీటిపారుదల తర్వాత ఆకులు త్వరగా ఆరిపోతాయి.',
  'Space plants and remove weeds so leaves dry faster in humid weather.':
      'తేమ వాతావరణంలో ఆకులు త్వరగా ఆరడానికి మొక్కల దూరం పెంచి కలుపు తీయండి.',
  'Proper plant spacing and morning watering keep leaves and air drier.':
      'సరైన మొక్కల దూరం మరియు ఉదయం నీరు పెట్టడంతో ఆకులు, గాలి పొడిగా ఉంటాయి.',
  'Mulch the beds': 'పడకలపై మల్చింగ్ చేయండి',
  'Mulch blocks spores splashing from soil onto leaves during rain or watering.':
      'వర్షం లేదా నీరు పెట్టినప్పుడు నేల నుండి ఆకులపై చిమ్మే బీజాంశాన్ని మల్చింగ్ అడ్డుకుంటుంది.',
  'Mulch reduces spore splash from the soil surface.':
      'నేల ఉపరితలం నుండి బీజాంశం చిమ్మడాన్ని మల్చింగ్ తగ్గిస్తుంది.',
  'Splashing water spreads leaf spot spores plant to plant.':
      'చిమ్మే నీరు ఆకుమచ్చ బీజాంశాన్ని మొక్క నుండి మొక్కకు వ్యాప్తి చేస్తుంది.',
  'Wet leaves spread Septoria - use drip or base watering.':
      'తడి ఆకులు సెప్టోరియాను వ్యాప్తి చేస్తాయి - డ్రిప్ లేదా మూలం వద్ద నీరు పెట్టండి.',
  'Keep the field from drying out completely; stressed rice is more prone to blast.':
      'పొలం పూర్తిగా పొడిగా ఉండకుండా చూసుకోండి; ఒత్తిడిలో వరికి బ్లాస్ట్ ఎక్కువ వస్తుంది.',
  'Greenhouses and polytunnels need vents opened when humidity rises.':
      'గ్రీన్‌హౌస్‌లు, పాలీటనల్‌లలో తేమ పెరిగినప్పుడు వెంటిలేషన్ తెరవండి.',
  'Bacteria enter through cuts from tools, insects or wind damage.':
      'పనిముట్లు, కీటకాలు లేదా గాలి నుండి వచ్చే కోతల ద్వారా బ్యాక్టీరియా లోపలికి వెళతాయి.',
  'Bacterial leaf blight spreads fast in warm, wet fields - a short drain can slow it.':
      'వెచ్చని, తడి పొలాల్లో బ్యాక్టీరియా ఆకుమడత వేగంగా వ్యాపిస్తుంది - కొద్దిసేపు నీరు తీస్తే మందగిస్తుంది.',
  'Uproot badly affected plants to limit spread through the water.':
      'నీటి ద్వారా వ్యాప్తిని తగ్గించడానికి బాగా ప్రభావితమైన మొక్కలను పీకేయండి.',
  'Leaf curl is spread by whiteflies - inspect the underside of leaves.':
      'ఆకు మడత వ్యాధి తెల్ల ఈగల ద్వారా వ్యాప్తి చెందుతుంది - ఆకు కింది భాగాన్ని తనిఖీ చేయండి.',
  'Leaf curl viruses are spread by sucking pests - check leaf undersides.':
      'ఆకు మడత వైరస్‌లు పీల్చు పురుగుల ద్వారా వ్యాప్తి చెందుతాయి - ఆకు కింది భాగాన్ని తనిఖీ చేయండి.',
  'Excess nitrogen favors bacterial blight development.':
      'అధిక నత్రజని బ్యాక్టీరియా ఆకుమడతను పెంచుతుంది.',
  'Heavy nitrogen makes soft, dense growth that blast attacks easily.':
      'అధిక నత్రజనితో మృదువైన, దట్టమైన పెరుగుదల వస్తుంది, బ్లాస్ట్ సులభంగా దాడి చేస్తుంది.',
  'Blast usually starts in shaded, humid corners - check them first.':
      'బ్లాస్ట్ సాధారణంగా నీడ ఉన్న, తేమ మూలల్లో ప్రారంభమవుతుంది - ముందుగా అక్కడ తనిఖీ చేయండి.',
  'Northern corn leaf blight starts on lower leaves and moves upward.':
      'ఉత్తర మొక్కజొన్న ఆకుమడత కింది ఆకులపై ప్రారంభమై పైకి వ్యాపిస్తుంది.',
  'Conditions are currently favorable - keep monitoring regularly.':
      'పరిస్థితులు ప్రస్తుతం అనుకూలంగా ఉన్నాయి - క్రమం తప్పకుండా పరిశీలించండి.',
  'Conditions favor disease development, but no strong increase is expected in the next 48 hours.':
      'పరిస్థితులు వ్యాధి వృద్ధికి అనుకూలంగా ఉన్నాయి, కానీ తర్వాతి 48 గంటల్లో పెద్ద పెరుగుదల ఉండదు.',
  'Conditions look normal right now.': 'పరిస్థితులు ఇప్పుడు సాధారణంగా కనిపిస్తున్నాయి.',
  'These conditions are within a normal range.': 'ఈ పరిస్థితులు సాధారణ పరిధిలో ఉన్నాయి.',
  'These wet, warm conditions help disease spread.':
      'ఈ తడి, వెచ్చని పరిస్థితులు వ్యాధి వ్యాప్తికి తోడుగా ఉంటాయి.',
  'Humidity is high (82%).': 'తేమ ఎక్కువగా ఉంది (82%).',
  'Humidity is within a favorable range for some diseases.':
      'తేమ కొన్ని వ్యాధులకు అనుకూల పరిధిలో ఉంది.',
  'Humidity is within a typical range.': 'తేమ సాధారణ పరిధిలో ఉంది.',
  'Temperature (27 C) favors disease development.':
      'ఉష్ణోగ్రత (27°C) వ్యాధి వృద్ధికి అనుకూలంగా ఉంది.',
  'Temperature can favor some leaf diseases.': 'ఉష్ణోగ్రత కొన్ని ఆకు వ్యాధులను పెంచుతుంది.',
  'Temperature is not an extra warning by itself.': 'ఉష్ణోగ్రత స్వయంగా అదనపు హెచ్చరిక కాదు.',
  'High soil moisture can keep leaves wet longer.':
      'ఎక్కువ నేల తేమ ఆకులను ఎక్కువ సేపు తడిగా ఉంచుతుంది.',
  'Soil moisture looks typical.': 'నేల తేమ సాధారణంగా ఉంది.',
  'Soil is very wet.': 'నేల చాలా తడిగా ఉంది.',
  'Soil is very wet. Extra watering keeps leaves and roots damp and helps disease.':
      'నేల చాలా తడిగా ఉంది. అదనపు నీరు ఆకులు, వేర్లను తడిగా ఉంచి వ్యాధిని పెంచుతుంది.',
  'Soil moisture is low and the plant is under stress. Water at the base.':
      'నేల తేమ తక్కువగా ఉంది, మొక్క ఒత్తిడిలో ఉంది. మూలం వద్ద నీరు పెట్టండి.',
  'Soil is dry; the plant is under stress.': 'నేల పొడిగా ఉంది; మొక్క ఒత్తిడిలో ఉంది.',
  'Soil is dry; the plant may be under stress.': 'నేల పొడిగా ఉంది; మొక్క ఒత్తిడిలో ఉండవచ్చు.',
  'Rain is expected soon, which can increase the risk.':
      'త్వరలో వర్షం వచ్చే అవకాశం ఉంది, దీనితో ప్రమాదం పెరుగుతుంది.',
  'Rain was recorded recently.': 'ఇటీవల వర్షం నమోదైంది.',
  'Rain or worsening weather may increase disease pressure.':
      'వర్షం లేదా దెబ్బతిన్న వాతావరణం వ్యాధి ఒత్తిడిని పెంచుతుంది.',
  'Rain or worsening weather may increase disease risk. Check that leaves can dry quickly.':
      'వర్షం లేదా దెబ్బతిన్న వాతావరణం వ్యాధి ప్రమాదాన్ని పెంచుతుంది. ఆకులు త్వరగా ఆరిపోతాయో చూసుకోండి.',
  'The weather is expected to improve.': 'వాతావరణం మెరుగవుతుందని భావిస్తున్నారు.',
  'The weather is expected to stay stable.': 'వాతావరణం స్థిరంగా ఉంటుందని భావిస్తున్నారు.',
  'The weather outlook is getting worse (more rain expected).':
      'వాతావరణం దెబ్బతింటుందని అంచనా (మరిన్ని వర్షాలు ఆశిస్తున్నారు).',
  'Weather outlook is stable or improving.': 'వాతావరణం స్థిరంగా లేదా మెరుగవుతోంది.',
  'HIGH HUMIDITY and rain can favor disease development. This is an estimate, not a guarantee.':
      'ఎక్కువ తేమ, వర్షం వ్యాధి వృద్ధికి అనుకూలంగా ఉంటాయి. ఇది అంచనా, హామీ కాదు.',
  'Environmental condition may increase disease risk.':
      'పర్యావరణ పరిస్థితి వ్యాధి ప్రమాదాన్ని పెంచుతుంది.',
  'Low light can slow drying after rain.': 'తక్కువ వెలుతురుతో వర్షం తర్వాత ఆరడం మందగిస్తుంది.',
  'Light level looks usable for the crop.': 'వెలుతురు పంటకు అనువుగా ఉంది.',
  'Humid conditions help it spread.': 'తేమ పరిస్థితులు దీని వ్యాప్తికి తోడుగా ఉంటాయి.',
  'The weather outlook may help it spread.': 'వాతావరణ రుజువు దీని వ్యాప్తికి తోడుగా ఉండవచ్చు.',
  'Conditions should be monitored.': 'పరిస్థితులను పరిశీలించాలి.',
  'A recent scan already showed high risk.': 'ఇటీవలి స్కాన్ ఇప్పటికే అధిక ప్రమాదాన్ని చూపింది.',
  'No disease was detected.': 'వ్యాధి గుర్తించబడలేదు.',
  'Not enough readings yet for a chart.': 'చార్ట్ కోసం తగినంత రీడింగ్‌లు ఇంకా లేవు.',
  'Calculated only from scans stored on this device or backend.':
      'ఈ పరికరం లేదా బ్యాకెండ్‌లో సేవ్ చేసిన స్కాన్‌ల నుండి మాత్రమే లెక్కించబడింది.',
  'Open the explanation to understand the evidence behind this estimate.':
      'ఈ అంచనా వెనుక ఉన్న ఆధారాలను అర్థం చేసుకోవడానికి వివరణను తెరవండి.',
  'Use the action list as guidance and confirm treatment decisions locally.':
      'చర్యల జాబితాను మార్గదర్శకంగా తీసుకుని చికిత్స నిర్ణయాలను స్థానికంగా ఖరారు చేసుకోండి.',
  'Plant identification is uncertain. Please capture a clearer image of the leaf and include the complete leaf in the frame.':
      'మొక్క గుర్తింపు అనిశ్చితంగా ఉంది. దయచేసి ఆకు యొక్క స్పష్టమైన చిత్రాన్ని తీసి పూర్తి ఆకు ఫ్రేమ్‌లో ఉంచండి.',
  'Early Blight was detected on the leaf (91% confidence).':
      'ఆకుపై అర్లీ బ్లైట్ గుర్తించబడింది (91% నమ్మకం).',
  'Maintain steady watering, spacing and clean field conditions.':
      'నిత్యం నీరు పెట్టడం, మొక్కల దూరం, శుభ్రమైన పొలం పరిస్థితులు కొనసాగించండి.',
  'Note affected plant count': 'ప్రభావిత మొక్కల సంఖ్యను నమోదు చేయండి',
  'Remove spotted lower leaves with clean tools and destroy them away from the field.':
      'శుభ్రమైన పనిముట్లతో మచ్చలున్న కింది ఆకులను కత్తిరించి పొలం నుండి దూరంగా నాశనం చేయండి.',
  'Showing cached or simulated information. Live sensors and AI are not confirmed.':
      'కాషెడ్ లేదా సిమ్యులేటెడ్ సమాచారం చూపిస్తున్నాం. ప్రత్యక్ష సెన్సర్‌లు, AI నిర్ధారించబడలేదు.',
  'Stressed plants show worse rust; keep nutrition balanced. Confirm locally.':
      'ఒత్తిడిలో ఉన్న మొక్కలలో రస్ట్ ఎక్కువ కనిపిస్తుంది; పోషణ సమతుల్యంగా ఉంచండి. స్థానికంగా ఖరారు చేసుకోండి.',
  'Setting up your farm...': 'మీ పొలం సిద్ధమవుతోంది...',
  'Get started': 'ప్రారంభించండి',
  'Continue': 'కొనసాగించండి',
  'Skip': 'దాటవేయండి',
  'Next': 'తర్వాత',
  'Select language': 'భాషను ఎంచుకోండి',
  'Your name': 'మీ పేరు',
  'Tell us your name so we can greet you on your farm dashboard.':
      'మీ పొల డాష్‌బోర్డ్‌లో స్వాగతం పలుకుటకు మీ పేరు చెప్పండి.',

  // ----- audit: status labels / UI chrome -----
  'OFFLINE': 'ఆఫ్‌లైన్',
  'AI identified a different crop': 'AI వేరే పంటను గుర్తించింది',
  'Uncertain identification': 'గుర్తింపు అనిశ్చితంగా ఉంది',
  'Identification not reliable': 'గుర్తింపు నమ్మదగినది కాదు',
  'Check selected crop': 'ఎంచుకున్న పంటను తనిఖీ చేయండి',
  'Identified crop:': 'గుర్తించిన పంట:',
  'SIMULATED': 'సిమ్యులేటెడ్',
  'CACHED / SIMULATED': 'కాషెడ్ / సిమ్యులేటెడ్',
  'CONNECTED': 'కనెక్ట్ అయింది',
  'LIVE DATA': 'ప్రత్యక్ష డేటా',
  'SCAN CROP': 'పంటను స్కాన్ చేయండి',
  'Condition': 'స్థితి',
  'Crop': 'పంట',
  'Current risk': 'ప్రస్తుత ప్రమాదం',
  'Severity': 'తీవ్రత',
  'Detected': 'గుర్తించబడింది',
  'Disease detected': 'వ్యాధి గుర్తించబడింది',
  'Disease detections': 'వ్యాధి గుర్తింపులు',
  'Plant identification': 'మొక్క గుర్తింపు',
  'Analytics': 'విశ్లేషణలు',
  'Multimodal analysis': 'బహుళ మాధ్యమ విశ్లేషణ',
  'Quick actions': 'తక్షణ చర్యలు',
  'Total scans': 'మొత్తం స్కాన్‌లు',
  'Healthy scans': 'ఆరోగ్యకరమైన స్కాన్‌లు',
  'Average confidence': 'సగటు నమ్మకం',
  'Average risk': 'సగటు ప్రమాదం',
  'Most detected condition': 'ఎక్కువగా గుర్తించిన స్థితి',
  'Just now': 'ఇప్పుడే',
  '1 day': '1 రోజు',
  '2-3 days': '2-3 రోజులు',
  '3-5 days': '3-5 రోజులు',
  '7 days': '7 రోజులు',
  'Please enter your name': 'దయచేసి మీ పేరు నమోదు చేయండి',
  'Could not save your name. Please try again.':
      'మీ పేరు సేవ్ చేయబడలేదు. దయచేసి మళ్లీ ప్రయత్నించండి.',
  'How healthy is my crop right now?': 'నా పంట ఇప్పుడు ఎంత ఆరోగ్యంగా ఉంది?',
  'AI-powered crop intelligence.': 'AI ఆధారిత పంట మేధస్సు.',
  'AgriSentry combines all of this before recommending action.':
      'సిఫారసు చేసే ముందు AgriSentry ఇవన్నీ కలిపి చూస్తుంది.',
  'Weather Intelligence': 'వాతావరణ మేధస్సు',
  'Driven by': 'ప్రభావిత కారకాలు',
  'ESTIMATED RISK': 'అంచనా వేసిన ప్రమాదం',
  'ESTIMATED FUTURE RISK': 'అంచనా వేసిన భవిష్యత్తు ప్రమాదం',
  'CURRENT ENVIRONMENTAL RISK': 'ప్రస్తుత పర్యావరణ ప్రమాదం',
  'DEMO MODEL - rule-based demo estimate, not a trained model':
      'డెమో మోడల్ - నియమ ఆధారిత డెమో అంచనా, శిక్షణ పొందిన మోడల్ కాదు',
  'demo_rules_v1: deterministic demo estimate for the selected crop':
      'demo_rules_v1: ఎంచుకున్న పంటకు నిర్ధారిత డెమో అంచనా',
  'TensorFlow Lite model not bundled yet - awaiting trained model export':
      'TensorFlow Lite మోడల్ ఇంకా చేర్చబడలేదు - శిక్షణ పొందిన మోడల్ కోసం వేచి ఉన్నాము',
  'No .tflite model is bundled with this build.':
      'ఈ బిల్డ్‌లో .tflite మోడల్ చేర్చబడలేదు.',
  'TFLite model required for true inference.':
      'నిజమైన అంచనాకు TFLite మోడల్ అవసరం.',
  'Backend unavailable': 'బ్యాకెండ్ అందుబాటులో లేదు',
  'The analysis service is unavailable. Check your connection and try again.':
      'విశ్లేషణ సేవ అందుబాటులో లేదు. మీ కనెక్షన్‌ను తనిఖీ చేసి మళ్లీ ప్రయత్నించండి.',
  'No risk assessment is available yet.': 'ఇంకా ప్రమాద అంచనా అందుబాటులో లేదు.',
  'No reading': 'రీడింగ్ లేదు',
  'Sensor feed is simulated': 'సెన్సర్ ఫీడ్ సిమ్యులేటెడ్',
  'ESP32 live readings are not confirmed. Values are development or fallback data.':
      'ESP32 ప్రత్యక్ష రీడింగ్‌లు నిర్ధారించబడలేదు. విలువలు అభివృద్ధి లేదా ఫాల్‌బ్యాక్ డేటా.',
};

/// Sentence-level templates for strings containing numbers / disease names.
final List<(RegExp, List<String> Function(RegExpMatch))> _teTemplates = [
  (
    RegExp(r'^(.+?) was detected on the leaf \((\d+)% confidence\)$'),
    (m) => ['${_disease(m[1]!)} ఆకుపై కనుగొనబడింది (${m[2]}% నమ్మకం)']
  ),
  (
    RegExp(r'^Humidity is very high \((\d+)%\)$'),
    (m) => ['తేమ చాలా ఎక్కువగా ఉంది (${m[1]}%)']
  ),
  (
    RegExp(r'^Humidity is high \((\d+)%\)$'),
    (m) => ['తేమ ఎక్కువగా ఉంది (${m[1]}%)']
  ),
  (
    RegExp(r'^Temperature \((\d+) ?°?C\) favors disease development$'),
    (m) => ['ఉష్ణోగ్రత (${m[1]}°C) వ్యాధి వృద్ధికి అనుకూలంగా ఉంది']
  ),
  (
    RegExp(r'^The leaf shows signs of (.+)$'),
    (m) => ['${_disease(m[1]!)} లక్షణాలు ఆకుపై కనిపిస్తున్నాయి']
  ),
  (
    RegExp(r'^The AI is (\d+)% sure of this$'),
    (m) => ['AI దీని గురించి ${m[1]}% ఖచ్చితంగా ఉంది']
  ),
  (
    RegExp(r'^Temperature is (-?[\d.]+) ?°?C, humidity (\d+)% and soil moisture (\d+)%$'),
    (m) => ['ఉష్ణోగ్రత ${m[1]}°C, తేమ ${m[2]}%, నేల తేమ ${m[3]}%']
  ),
  (
    RegExp(r'^Right now: (.+), (-?[\d.]+) ?°?C$'),
    (m) => ['ప్రస్తుతం: ${m[1]}, ${m[2]}°C']
  ),
  (
    RegExp(r'^(\d+) recent scans? already showed high risk$'),
    (m) => ['${m[1]} ఇటీవలి స్కాన్‌లు ఇప్పటికే అధిక ప్రమాదాన్ని చూపించాయి']
  ),
  (
    RegExp(r'^Your crop is at (low|medium|high) risk \((\d+)/100\)$'),
    (m) => ['మీ పంటకు ${_teLevels[m[1]] ?? m[1]} ప్రమాదం ఉంది (${m[2]}/100)']
  ),
  (
    // Fusion summary: '<Disease> was detected.' with a KB disease name.
    RegExp(r'^(Healthy|Early Blight|Late Blight|Bacterial Spot|Leaf Mold|'
        r'Septoria Leaf Spot|Rice Blast|Rice Leaf Blight|Cotton Leaf Curl|'
        r'Chilli Leaf Spot|Chilli Leaf Curl|Maize Leaf Blight|Maize Rust|'
        r'Tomato Leaf Mold) was detected\.$'),
    (m) => ['${_disease(m[1]!)} గుర్తించబడింది.']
  ),
  (
    // Fusion risk sentence with a lowercase disease name embedded.
    RegExp(r'^Risk is expected to increase because conditions favor (.+?) '
        r'progression in the next 48 hours\.$'),
    (m) => [
      'తర్వాతి 48 గంటల్లో ${m[1]} వ్యాధి పెరుగుదలకు పరిస్థితులు అనుకూలంగా ఉన్నాయి, '
          'కాబట్టి ప్రమాదం పెరుగుతుందని అంచనా.'
    ]
  ),
];

String _disease(String en) => _teDiseases[en.trim()] ?? en.trim();
String _hindiSentence(String s) {
  final detected = RegExp(
          r'^(.+?) was detected on the leaf \((\d+)% confidence\)$')
      .firstMatch(s);
  if (detected != null) {
    return '${_hiDiseases[detected[1]!.trim()] ?? detected[1]} पत्ती पर पाया गया (${detected[2]}% विश्वास)';
  }
  final humidity = RegExp(r'^Humidity is (very high|high) \((\d+)%\)$')
      .firstMatch(s);
  if (humidity != null) {
    return 'नमी ${humidity[1] == 'very high' ? 'बहुत अधिक' : 'अधिक'} है (${humidity[2]}%)';
  }
  final temperature = RegExp(
          r'^Temperature \((\d+) ?°?C\) favors disease development$')
      .firstMatch(s);
  if (temperature != null) {
    return 'तापमान (${temperature[1]}°C) रोग के विकास के अनुकूल है';
  }
  final signs = RegExp(r'^The leaf shows signs of (.+)$').firstMatch(s);
  if (signs != null) {
    return '${_hiDiseases[signs[1]!.trim()] ?? signs[1]} के लक्षण पत्ती पर दिखाई दे रहे हैं';
  }
  final confidence = RegExp(r'^The AI is (\d+)% sure of this$').firstMatch(s);
  if (confidence != null) return 'AI को इस पर ${confidence[1]}% विश्वास है';
  final readings = RegExp(
          r'^Temperature is (-?[\d.]+) ?°?C, humidity (\d+)% and soil moisture (\d+)%$')
      .firstMatch(s);
  if (readings != null) {
    return 'तापमान ${readings[1]}°C, नमी ${readings[2]}% और मिट्टी की नमी ${readings[3]}% है';
  }
  final rightNow = RegExp(r'^Right now: (.+), (-?[\d.]+) ?°?C$')
      .firstMatch(s);
  if (rightNow != null) return 'अभी: ${rightNow[1]}, ${rightNow[2]}°C';
  final recent = RegExp(r'^(\d+) recent scans? already showed high risk$')
      .firstMatch(s);
  if (recent != null) return '${recent[1]} हाल के स्कैन में पहले ही उच्च जोखिम दिखा';
  final cropRisk =
      RegExp(r'^Your crop is at (low|medium|high) risk \((\d+)/100\)$')
          .firstMatch(s);
  if (cropRisk != null) {
    return 'आपकी फसल में ${_hiLevels[cropRisk[1]!.toUpperCase()] ?? cropRisk[1]} जोखिम है (${cropRisk[2]}/100)';
  }
  final detectedSentence = RegExp(
          r'^(Healthy|Early Blight|Late Blight|Bacterial Spot|Leaf Mold|'
          r'Septoria Leaf Spot|Rice Blast|Rice Leaf Blight|Cotton Leaf Curl|'
          r'Chilli Leaf Spot|Chilli Leaf Curl|Maize Leaf Blight|Maize Rust|'
          r'Tomato Leaf Mold) was detected\.$')
      .firstMatch(s);
  if (detectedSentence != null) {
    return '${_hiDiseases[detectedSentence[1]!.trim()] ?? detectedSentence[1]} पाया गया।';
  }
  final riskIncrease = RegExp(
          r'^Risk is expected to increase because conditions favor (.+?) progression in the next 48 hours\.$')
      .firstMatch(s);
  if (riskIncrease != null) {
    return 'अगले 48 घंटों में ${riskIncrease[1]} रोग बढ़ने के लिए स्थितियां अनुकूल हैं, इसलिए जोखिम बढ़ने का अनुमान है।';
  }
  return s;
}

String _trSentence(String s) {
  final exact = LanguageService.instance.isHindi ? _hi[s] : _te[s];
  if (exact != null) return exact;
  if (LanguageService.instance.isHindi) return _hindiSentence(s);
  for (final (pattern, build) in _teTemplates) {
    final m = pattern.firstMatch(s);
    if (m != null) return build(m).join(' ');
  }
  return s; // unknown string - fall back to English for this sentence
}

String _trDynamic(String en) {
  final trimmed = en.trim();
  final endsWithDot = trimmed.endsWith('.');
  final body = endsWithDot ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  final parts = body.split('. ');
  final out = <String>[];
  for (final p in parts) {
    if (p.startsWith('Main reasons: ')) {
      final label = LanguageService.instance.isHindi ? 'मुख्य कारण: ' : 'ప్రमुख కారణాలు: ';
      out.add('$label${_trSentence(p.substring('Main reasons: '.length))}');
    } else {
      out.add(_trSentence(p));
    }
  }
  var joined = out.join('. ');
  if (endsWithDot && !joined.endsWith('.')) joined = '$joined.';
  return joined;
}

/// Translate a fixed UI string or a backend-generated English sentence.
/// English mode returns the input unchanged; unknown Telugu sentences fall
/// back to the original English for that sentence.
String tr(String en) {
  if (LanguageService.instance.current == AppLanguage.english) return en;
  final exact = LanguageService.instance.isHindi ? _hi[en] : _te[en];
  if (exact != null) return exact;
  return _trDynamic(en);
}

/// Risk level / urgency badge text.
String trLevel(String level) {
  if (LanguageService.instance.current == AppLanguage.english) {
    return level.toUpperCase();
  }
  final levels = LanguageService.instance.isHindi ? _hiLevels : _teLevels;
  return levels[level.toUpperCase()] ?? level.toUpperCase();
}

/// Disease / condition name.
String trDisease(String name) {
  if (LanguageService.instance.current == AppLanguage.english) return name;
  final diseases =
      LanguageService.instance.isHindi ? _hiDiseases : _teDiseases;
  return diseases[name.trim()] ?? name.trim();
}

String confidenceLabel(int pct) =>
    LanguageService.instance.isHindi
        ? 'विश्वास $pct%'
        : LanguageService.instance.isTelugu
            ? 'नమ్మకం $pct%'
            : '$pct% confidence';

String sureLabel(int pct) =>
    LanguageService.instance.isHindi
        ? '$pct% निश्चित'
        : LanguageService.instance.isTelugu
            ? '$pct% ఖచ్చితంగా'
            : '$pct% sure';

// ---------------------------------------------------------------------------
// Spoken text for the TTS button on each result screen
// ---------------------------------------------------------------------------

String spokenResult(ImageAnalysisResult r) {
  final d = r.disease;
  final f48 = r.futureRisk.h48?.level ?? 'LOW';
  if (LanguageService.instance.isHindi) {
    return 'रोग: ${trDisease(d.name)}। विश्वास ${d.confidencePct} प्रतिशत। '
        'वर्तमान जोखिम: ${trLevel(r.risk.level)}। '
        '48 घंटे का जोखिम: ${trLevel(f48)}।';
  }
  if (LanguageService.instance.isTelugu) {
    return 'వ్యాధి: ${trDisease(d.name)}. నమ్మకం ${d.confidencePct} శాతం. '
        'ప్రస్తుత ప్రమాదం: ${trLevel(r.risk.level)}. '
        '48 గంటలలో ప్రమాదం: ${trLevel(f48)}.';
  }
  return 'Disease: ${d.name}. Confidence ${d.confidencePct} percent. '
      'Current risk: ${r.risk.level}. Risk in 48 hours: $f48.';
}

String spokenWhy(ImageAnalysisResult r) {
  final summary = tr(r.explanation.summary);
  final factors = r.risk.factors.map(tr).join(' ');
  return factors.isEmpty ? summary : '$summary $factors';
}

String spokenRecs(ImageAnalysisResult r) {
  final c = r.recommendation.categories;
  final items = [...c.doNow, ...c.manage, ...c.prevent, ...c.monitor, ...c.water, ...c.environment]
      .take(5)
      .map((i) => tr(i.title))
      .join('. ');
  if (LanguageService.instance.isHindi) {
    return 'सुझाए गए उपाय: $items।';
  }
  if (LanguageService.instance.isTelugu) {
    return 'సూచించిన చర్యలు: $items.';
  }
  return 'Recommended actions: $items.';
}
