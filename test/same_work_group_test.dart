import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:venera/foundation/comic_state_repository.dart';
import 'package:venera/foundation/domain_database.dart';
import 'package:venera/foundation/source_platform.dart';
import 'package:venera/foundation/search/same_work_group.dart';
import 'package:venera/foundation/search/search_relevance.dart';
import 'package:venera/foundation/search/title_normalizer.dart';
import 'helpers/search_fixture.dart';

SearchCandidate candidate(
  String title,
  String source,
  int sourceOrder, {
  String? work,
  int item = 0,
  int page = 0,
  String? id,
}) => SearchCandidate(
  comic: searchComic(title, source: source, id: id, cover: 'same-cover'),
  sourceOrder: sourceOrder,
  itemOrder: item,
  pageOrder: page,
  sourceName: source,
  artifact: source,
  acceptedWorkId: work,
  title: SearchTitle(title),
  relevance: SearchRelevanceMatcher('神之塔').match(SearchTitle(title)),
);

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      open.overrideFor(
        OperatingSystem.windows,
        () => DynamicLibrary.open('winsqlite3.dll'),
      );
    }
  });

  test('accepted work groups keep each original comic and source identity', () {
    final a = candidate('神之塔', 'a', 0, work: 'accepted');
    final b = candidate('Tower of God', 'b', 1, work: 'accepted');
    final groups = rankBestMatches([b, a]);
    expect(groups, hasLength(1));
    expect(groups.single.alternatives.map((c) => c.comic), [
      same(a.comic),
      same(b.comic),
    ]);
    expect(groups.single.anchor, same(a));
    expect(groups.single.best, same(a));
    expect(groupingConfidence(a, b), SearchGroupingConfidence.aliasSafe);
  });

  test('equal or similar titles and shared covers alone never auto-group', () {
    final a = candidate('神之塔', 'a', 0);
    final b = candidate('神之塔', 'b', 1);
    final c = candidate('神之犬', 'c', 2);
    expect(groupingConfidence(a, b), SearchGroupingConfidence.probable);
    expect(rankBestMatches([a, b, c]), hasLength(3));
  });

  test(
    'provider/page/item order is stable and only duplicate identity collapses',
    () {
      final a = candidate('weak', 'a', 0, page: 0, item: 1, id: 'a');
      final b = candidate('weak', 'a', 0, page: 1, id: 'b');
      final c = candidate('weak', 'b', 1, id: 'a');
      final results = rankBestMatches([c, b, a, a]);
      expect(results.map((g) => g.best), [same(a), same(b), same(c)]);
    },
  );

  test(
    'read-only lookup excludes high-confidence candidates and rejections',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'venera-search-work-',
      );
      final domain = DomainDatabase();
      await domain.init(directory.path);
      final repository = ComicStateRepository(domain: domain);
      final a = searchComic('神之塔', source: 'a');
      final b = searchComic('Tower of God', source: 'b');
      final c = searchComic('神之塔', source: 'c');
      try {
        repository.mirrorComic(a);
        repository.mirrorComic(b);
        repository.mirrorComic(c);
        final work = domain.linkSourceComics(
          sourcePlatform: SourcePlatformResolver.fromSourceKey(a.sourceKey),
          sourceComicId: a.id,
          targetPlatform: SourcePlatformResolver.fromSourceKey(b.sourceKey),
          targetSourceComicId: b.id,
        );
        final cId = repository.identityFor(c.sourceKey, c.id).comicId;
        domain.db.execute('DELETE FROM work_sources WHERE comic_id = ?;', [
          cId,
        ]);
        domain.db.execute(
          'INSERT INTO work_sources (work_id,comic_id,link_status,link_source,confidence,created_at,updated_at) VALUES (?,?,\'candidate\',\'auto\',0.95,1,1);',
          [work, cId],
        );
        final before = domain.db
            .select('SELECT total_changes() AS n;')
            .single['n'];
        domain.db.execute('PRAGMA query_only = ON;');
        final accepted = repository.peekAcceptedSearchWorks([
          a,
          b,
          c,
          searchComic('unknown'),
        ]);
        expect(
          accepted.keys,
          containsAll([(a.sourceKey, a.id), (b.sourceKey, b.id)]),
        );
        expect(accepted, isNot(contains((c.sourceKey, c.id))));
        expect(
          accepted[(a.sourceKey, a.id)]!.aliases,
          containsAll(['神之塔', 'Tower of God']),
        );
        expect(
          domain.db.select('SELECT total_changes() AS n;').single['n'],
          before,
        );
        domain.db.execute('PRAGMA query_only = OFF;');
        domain.rejectWorkSource(
          workId: work,
          comicId: repository.identityFor(b.sourceKey, b.id).comicId,
        );
        domain.db.execute('PRAGMA query_only = ON;');
        final afterReject = repository.peekAcceptedSearchWorks([a, b]);
        expect(afterReject, contains((a.sourceKey, a.id)));
        expect(afterReject, isNot(contains((b.sourceKey, b.id))));
      } finally {
        domain.close();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test('search lookup does not initialize a database', () {
    final domain = DomainDatabase();
    expect(
      ComicStateRepository(
        domain: domain,
      ).peekAcceptedSearchWorks([searchComic('new')]),
      isEmpty,
    );
    expect(domain.isInitialized, isFalse);
  });
}
