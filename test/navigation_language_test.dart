import 'package:flutter_test/flutter_test.dart';
import 'package:blind_way/src/config/languages.dart';
import 'package:blind_way/src/config/navigation_strings.dart';
import 'package:blind_way/src/config/navigation_translations.dart';
import 'package:blind_way/src/services/api_service.dart';

void main() {
  test('language endpoints have no empty query or fragment suffix', () {
    for (final path in ['/speech', '/navigation/translate']) {
      final uri = navigationMediaUri(
        'wss://example.test/live?language=kn-IN#unused',
        path,
      );
      expect(uri.toString(), 'https://example.test$path');
      expect(uri.hasQuery, false);
      expect(uri.hasFragment, false);
    }
  });
  test('every offered language has a complete bundled navigation catalog', () {
    final source = navigationTranslations['en-IN']!;
    final placeholders = RegExp(r'\{\w+\}');
    for (final locale in AppLanguages.labels.keys.where((x) => x != 'auto')) {
      final catalog = navigationTranslations[locale]!;
      expect(catalog.keys.toSet(), source.keys.toSet(), reason: locale);
      for (final entry in catalog.entries) {
        expect(entry.value.trim(), isNotEmpty);
        expect(
          placeholders.allMatches(entry.value).map((m) => m[0]).toList()
            ..sort(),
          placeholders.allMatches(entry.key).map((m) => m[0]).toList()..sort(),
          reason: '$locale: ${entry.key}',
        );
      }
      if (!locale.startsWith('en-')) {
        expect(
          catalog['Walking navigation stopped.'],
          isNot('Walking navigation stopped.'),
          reason: locale,
        );
        expect(
          catalog['GPS is inaccurate or unavailable. Directions are paused until location improves.'],
          isNot(
            'GPS is inaccurate or unavailable. Directions are paused until location improves.',
          ),
          reason: locale,
        );
      }
    }
  });
  test(
    'translated prompts preserve address and distance values without reinterpreting them',
    () {
      const address = 'Church Road {metres}';
      final words = NavigationStrings('kn-IN');
      final result = words.text(
        'I found {name}, {address}. Is this the place you mean? After the beep, say yes to choose this place, no for another place, or say repeat to hear this address again.',
        {'name': 'Clinic 12', 'address': address},
      );
      expect(result, contains(address));
      expect(result, contains('Clinic 12'));
      expect(result, isNot(contains('Is this the place')));
      expect(
        NavigationStrings('auto').text('Walking navigation stopped.'),
        'Walking navigation stopped.',
      );
    },
  );
}
