import 'languages.dart';
import 'navigation_translations.dart';

/// Bundled prompts avoid a translation request while walking or during GPS loss.
class NavigationStrings {
  NavigationStrings(String locale)
    : locale = locale == 'auto' ? 'en-IN' : AppLanguages.normalize(locale);
  final String locale;
  String text(String source, [Map<String, Object> values = const {}]) {
    final translated = navigationTranslations[locale]?[source] ?? source;
    return translated.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (m) => values[m[1]]?.toString() ?? m[0]!,
    );
  }
}
