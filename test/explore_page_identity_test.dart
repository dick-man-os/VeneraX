import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_source/explore_identity.dart';

// Dummy ComicSource for testing
class DummyComicSource extends ComicSource {
  DummyComicSource(String key, String name, List<ExplorePageData> explorePages)
      : super(
          name, key, null, null, null, null, explorePages, null, null, null,
          null, null, null, null, '', '', '', null, null, null,
          null, null, null, null, null, const {}, null, null, null, false, false, null, null
        );
}

// Dummy ExplorePageData for testing
class DummyExplorePageData extends ExplorePageData {
  DummyExplorePageData(String title)
      : super(
          title,
          ExplorePageType.singlePageWithMultiPart,
          null,
          null,
          null,
          null,
        );
}

void main() {
  group('ExplorePageIdentity', () {
    final sourceA = DummyComicSource(
      'source_a',
      'Source A',
      [DummyExplorePageData('Popular'), DummyExplorePageData('Latest')],
    );

    final sourceB = DummyComicSource(
      'source_b',
      'Source B',
      [DummyExplorePageData('Popular'), DummyExplorePageData('Latest')],
    );

    final sources = [sourceA, sourceB];

    test('A. source_a::Popular != source_b::Popular', () {
      final idA = ExplorePageIdentity.create('source_a', 'Popular');
      final idB = ExplorePageIdentity.create('source_b', 'Popular');
      expect(idA, isNot(equals(idB)));
    });

    test('B. Two dummy sources expose four independent identities', () {
      final ids = <String>{
        ExplorePageIdentity.create('source_a', 'Popular'),
        ExplorePageIdentity.create('source_a', 'Latest'),
        ExplorePageIdentity.create('source_b', 'Popular'),
        ExplorePageIdentity.create('source_b', 'Latest'),
      };
      expect(ids.length, equals(4));
    });

    test('C. duplicate Settings map identities do not overwrite each other', () {
      final map = <String, String>{};
      final idA = ExplorePageIdentity.create('source_a', 'Popular');
      final idB = ExplorePageIdentity.create('source_b', 'Popular');
      map[idA] = 'dataA';
      map[idB] = 'dataB';
      expect(map.length, equals(2));
      expect(map[idA], equals('dataA'));
      expect(map[idB], equals('dataB'));
    });

    test('D. source_a::Popular resolves only Source A', () {
      final id = ExplorePageIdentity.create('source_a', 'Popular');
      final resolved = ExplorePageIdentity.resolve(id, sources);
      expect(resolved, isNotNull);
      expect(resolved!.source.key, equals('source_a'));
      expect(resolved.data.title, equals('Popular'));
    });

    test('E. legacy migrates to FIRST matching source', () {
      final normalizedPop = ExplorePageIdentity.normalize('Popular', sources);
      expect(normalizedPop, equals('source_a::Popular'));

      final normalizedLat = ExplorePageIdentity.normalize('Latest', sources);
      expect(normalizedLat, equals('source_a::Latest'));
    });

    test('F. migration is idempotent', () {
      final normalized = ExplorePageIdentity.normalize('source_b::Popular', sources);
      expect(normalized, equals('source_b::Popular'));
    });

    test('G. adding a second source with the same Explore page title works', () {
      final pages = <String>[];
      // Install Source A Popular
      final idA = ExplorePageIdentity.normalize('Popular', [sourceA]);
      pages.add(idA);
      // Install Source B Popular
      final idB = ExplorePageIdentity.normalize('Popular', [sourceB]);
      pages.add(idB);

      expect(pages.length, equals(2));
      expect(pages.contains('source_a::Popular'), isTrue);
      expect(pages.contains('source_b::Popular'), isTrue);
    });

    test('H. validating/removing Source A preserves Source B', () {
      final pages = <String>['source_a::Popular', 'source_b::Popular'];
      // Source A is removed, only sourceB remains in active sources
      final activeSources = [sourceB];

      final validPages = <String>[];
      for (var page in pages) {
        if (ExplorePageIdentity.resolve(page, activeSources) != null) {
          validPages.add(page);
        }
      }

      expect(validPages.length, equals(1));
      expect(validPages.contains('source_b::Popular'), isTrue);
      expect(validPages.contains('source_a::Popular'), isFalse);
    });

    test('I. unresolved legacy value is preserved rather than deleted', () {
      final normalized = ExplorePageIdentity.normalize('UnknownTab', sources);
      expect(normalized, equals('UnknownTab'));
    });

    test('J. title containing "::" round-trips correctly', () {
      final id = ExplorePageIdentity.create('source_a', 'Weird::Tab::Name');
      expect(id, equals('source_a::Weird::Tab::Name'));

      final parsed = ExplorePageIdentity.tryParse(id);
      expect(parsed, isNotNull);
      expect(parsed!.sourceKey, equals('source_a'));
      expect(parsed.title, equals('Weird::Tab::Name'));

      final resolved = ExplorePageIdentity.resolve(id, [
        DummyComicSource('source_a', 'Source A', [DummyExplorePageData('Weird::Tab::Name')]),
      ]);
      expect(resolved, isNotNull);
      expect(resolved!.source.key, equals('source_a'));
      expect(resolved.data.title, equals('Weird::Tab::Name'));
    });

    test('Safely tryParse malformed non-string items or no separators', () {
      expect(ExplorePageIdentity.tryParse('Popular'), isNull);
      expect(ExplorePageIdentity.tryParse('source_a:Popular'), isNull); // missing double colon
      expect(ExplorePageIdentity.tryParse(''), isNull);
    });

    test('Production startup migration (migrateLegacyList) functions correctly', () {
      final legacyList = ['Popular', 'Latest', 'source_b::Popular'];
      final newExplorePages = ExplorePageIdentity.migrateLegacyList(legacyList, sources);

      expect(newExplorePages, isNotNull);
      expect(newExplorePages!.length, equals(3));
      expect(newExplorePages[0], equals('source_a::Popular'));
      expect(newExplorePages[1], equals('source_a::Latest'));
      expect(newExplorePages[2], equals('source_b::Popular'));

      // Idempotent check
      final secondMigration = ExplorePageIdentity.migrateLegacyList(newExplorePages, sources);
      expect(secondMigration, isNull);
    });
  });
}
