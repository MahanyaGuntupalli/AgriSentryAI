import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agrisentry_ai/services/translations.dart';

/// Translation-completeness validation (audit Phase 22).
///
/// Every static literal passed to tr()/trLevel()/trDisease() across lib/ must
/// exist as an exact key in BOTH the Hindi and Telugu dictionaries (or the
/// disease/level maps). Fails `flutter test` when a translation is missing,
/// so mixed-language output cannot silently return.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final root = Directory.current.path;
  final libDir = Directory('$root/lib');

  final source = File('$root/lib/services/translations.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  final literal = RegExp(r"'((?:[^'\\\n]|\\.)*)'");

  Set<String> mapKeys(String name) {
    final m = RegExp('Map<String, String>\\s+$name\\s*=\\s*\\{')
        .firstMatch(source);
    if (m == null) return {};
    var i = m.end;
    var depth = 1;
    var j = i;
    while (depth > 0 && j < source.length) {
      if (source[j] == '{') depth++;
      if (source[j] == '}') depth--;
      j++;
    }
    final body = source.substring(i, j - 1);
    final keys = <String>{};
    for (final match in RegExp("\\s*'((?:[^'\\\\]|\\\\.)*)'\\s*:")
        .allMatches(body)) {
      keys.add(match.group(1)!);
    }
    return keys;
  }

  final hi = mapKeys('_hi');
  final te = mapKeys('_te');
  final hiDiseases = mapKeys('_hiDiseases');
  final teDiseases = mapKeys('_teDiseases');
  final hiLevels = mapKeys('_hiLevels');
  final teLevels = mapKeys('_teLevels');

  bool covered(String key) =>
      (hi.contains(key) && te.contains(key)) ||
      (hiDiseases.contains(key) && teDiseases.contains(key)) ||
      (hiLevels.contains(key) && teLevels.contains(key));

  /// Collect every static literal passed to tr()/trLevel()/trDisease() in a
  /// Dart source file, joining Dart's adjacent string-literal concatenation.
  List<String> callSiteLiterals(String src) {
    src = src.replaceAll('\r\n', '\n');
    final out = <String>[];
    final call = RegExp(r"\b(?:tr|trLevel|trDisease)\(\s*'");
    for (final m in call.allMatches(src)) {
      final run = RegExp(
              r"'((?:[^'\\\n]|\\.)*)'(?:\s*'((?:[^'\\\n]|\\.)*)')*")
          .firstMatch(src.substring(m.start));
      if (run == null) continue;
      final parts = literal.allMatches(run.group(0)!).map((e) => e.group(1)!);
      out.add(parts.join());
    }
    return out;
  }

  test('disease and level maps are symmetric across languages', () {
    expect(hiDiseases.difference(teDiseases), isEmpty,
        reason: 'Telugu missing disease names: '
            '${hiDiseases.difference(teDiseases)}');
    expect(teDiseases.difference(hiDiseases), isEmpty,
        reason: 'Hindi missing disease names: '
            '${teDiseases.difference(hiDiseases)}');
    expect(hiLevels, teLevels, reason: 'risk level maps must match exactly');
  });

  test('every tr() call-site literal has a HI and TE translation', () {
    final missing = <String, List<String>>{};
    for (final f in libDir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('translations.dart')) continue;
      for (final s in callSiteLiterals(f.readAsStringSync())) {
        if (s.contains(r'$')) continue; // runtime interpolation
        if (!covered(s)) {
          missing.putIfAbsent(f.path, () => []).add(s);
        }
      }
    }
    expect(missing, isEmpty,
        reason: 'Missing translations (add to _hi AND _te in '
            'lib/services/translations.dart): $missing');
  });

  test('tr() translates and falls back safely', () async {
    await LanguageService.instance.set(AppLanguage.telugu);
    expect(tr('Scanning leaf...'), isNot(contains('Scanning')));
    // Unknown string: falls back to the original English for that sentence.
    expect(tr('Definitely not in the dictionary xyz'), contains('xyz'));

    await LanguageService.instance.set(AppLanguage.hindi);
    expect(tr('Scanning leaf...'), isNot(contains('Scanning')));

    await LanguageService.instance.set(AppLanguage.english);
    expect(tr('Scanning leaf...'), 'Scanning leaf...');
  });

  test('trDisease translates known diseases and keeps unknown readable', () async {
    await LanguageService.instance.set(AppLanguage.telugu);
    expect(trDisease('Tomato Leaf Mold'), isNot(equals('Tomato Leaf Mold')));
    expect(trDisease('Not A Real Disease'), 'Not A Real Disease');
    await LanguageService.instance.set(AppLanguage.english);
  });
}
