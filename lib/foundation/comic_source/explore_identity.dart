import 'package:venera/foundation/comic_source/comic_source.dart';

class ExplorePageIdentity {
  /// Create a composite identity from a source key and page title.
  static String create(String sourceKey, String title) {
    return '$sourceKey::$title';
  }

  /// Parse a composite identity back into its source key and title components.
  /// Splits only on the first '::' separator.
  static ({String sourceKey, String title})? tryParse(String value) {
    final idx = value.indexOf('::');
    if (idx == -1) {
      return null;
    }
    final sourceKey = value.substring(0, idx);
    final title = value.substring(idx + 2);
    return (sourceKey: sourceKey, title: title);
  }

  /// Normalizes a potentially legacy title-only value into a composite identity.
  /// If [value] already contains '::', it is returned unchanged.
  /// Otherwise, uses [sources] to find the first matching source that provides
  /// an explore page with this title. If found, returns the new composite identity.
  /// If not found, returns [value] unchanged (preserves unresolved).
  static String normalize(String value, Iterable<ComicSource> sources) {
    if (value.contains('::')) {
      return value;
    }
    for (var source in sources) {
      for (var page in source.explorePages) {
        if (page.title == value) {
          return create(source.key, value);
        }
      }
    }
    return value;
  }

  /// Resolves an identity to the exact ComicSource and ExplorePageData.
  /// Supports both composite identities and legacy title-only identities
  /// (for backwards compatibility fallback if needed).
  static ({ComicSource source, ExplorePageData data})? resolve(
    String identity,
    Iterable<ComicSource> sources,
  ) {
    final parsed = tryParse(identity);
    if (parsed != null) {
      final sourceKey = parsed.sourceKey;
      final title = parsed.title;
      for (var source in sources) {
        if (source.key == sourceKey) {
          for (var page in source.explorePages) {
            if (page.title == title) {
              return (source: source, data: page);
            }
          }
          break; // source matched but page not found
        }
      }
    } else {
      // Fallback for unresolved legacy identities at runtime
      for (var source in sources) {
        for (var page in source.explorePages) {
          if (page.title == identity) {
            return (source: source, data: page);
          }
        }
      }
    }
    return null;
  }

  /// Migrates a legacy list of explore pages to composite identities.
  /// Returns the new list, or null if no changes were needed.
  static List<String>? migrateLegacyList(List<dynamic> legacyList, Iterable<ComicSource> sources) {
    bool changed = false;
    var newExplorePages = <String>[];
    for (var page in legacyList) {
      if (page is String) {
        var normalized = normalize(page, sources);
        if (!newExplorePages.contains(normalized)) {
          newExplorePages.add(normalized);
        }
        if (normalized != page) {
          changed = true;
        }
      }
    }
    if (changed || legacyList.length != newExplorePages.length) {
      return newExplorePages;
    }
    return null;
  }
}
