import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/search/aggregated_search_controller.dart';
import 'package:venera/foundation/search/search_relevance.dart';
import 'helpers/search_fixture.dart';

Future<void> drain() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.value();
  }
}

void main() {
  final registered = <String>[];
  SearchProvider provider(
    String key,
    SearchFunction load, {
    String version = '1.0.0',
  }) {
    final source = searchSource(key, load, version: version);
    ComicSourceManager().add(source);
    registered.add(key);
    return SearchProvider(source);
  }

  tearDown(() {
    for (final key in registered) {
      ComicSourceManager().remove(key);
    }
    registered.clear();
  });

  test(
    'all completion permutations settle to the same ranking and keep weak results',
    () async {
      for (final order in [
        [0, 1, 2],
        [0, 2, 1],
        [1, 0, 2],
        [1, 2, 0],
        [2, 0, 1],
        [2, 1, 0],
      ]) {
        final pending = List.generate(3, (_) => Completer<Res<List<Comic>>>());
        final providers = [
          for (var i = 0; i < 3; i++)
            provider('p$i', (_, _, _) => pending[i].future),
        ];
        final controller = AggregatedSearchController(
          admission: SearchOperationAdmission(),
        );
        controller.search('神之塔', providers);
        for (final i in order) {
          pending[i].complete(
            Res([searchComic(i == 2 ? '神之塔' : 'weak', source: 'p$i')]),
          );
          await drain();
          expect(controller.bestMatches, hasLength(order.indexOf(i) + 1));
        }
        expect(controller.bestMatches.map((g) => g.best.comic.sourceKey), [
          'p2',
          'p0',
          'p1',
        ]);
        expect(controller.results.every((r) => r.comics.length == 1), isTrue);
        controller.dispose();
        for (final p in providers) {
          ComicSourceManager().remove(p.source.key);
        }
      }
    },
  );

  test(
    '100 providers admit four operations and one per runtime key across controllers',
    () async {
      final admission = SearchOperationAdmission();
      final pending = <Completer<Res<List<Comic>>>>[];
      var active = 0;
      var maximum = 0;
      final activeKeys = <String>{};
      final providers = [
        for (var i = 0; i < 100; i++)
          provider('p$i', (_, _, _) async {
            expect(activeKeys.add('p$i'), isTrue);
            active++;
            if (active > maximum) maximum = active;
            final c = Completer<Res<List<Comic>>>();
            pending.add(c);
            final result = await c.future;
            active--;
            activeKeys.remove('p$i');
            return result;
          }),
      ];
      final a = AggregatedSearchController(admission: admission);
      final b = AggregatedSearchController(admission: admission);
      a.search('神之塔', providers);
      b.search('Tower of God', providers.take(1).toList());
      expect(pending, hasLength(4));
      for (var i = 0; i < 101; i++) {
        expect(pending.length, greaterThan(i));
        pending[i].complete(const Res([]));
        await drain();
      }
      expect(maximum, 4);
      expect(active, 0);
      expect(a.pendingSources, 0);
      expect(b.pendingSources, 0);
      a.dispose();
      b.dispose();
    },
  );

  test(
    'rapid A B A replacement drops queued work and stale results; raw query retained',
    () async {
      final pending = <Completer<Res<List<Comic>>>>[];
      final queries = <String>[];
      final p = provider('a', (q, _, _) {
        queries.add(q);
        final c = Completer<Res<List<Comic>>>();
        pending.add(c);
        return c.future;
      });
      final controller = AggregatedSearchController(
        admission: SearchOperationAdmission(),
      );
      controller.search('神之塔', [p]);
      controller.search('Tower of God', [p]);
      controller.search(' 神之塔 ', [p]);
      expect(queries, ['神之塔']);
      pending[0].complete(Res([searchComic('stale')]));
      await drain();
      expect(controller.bestMatches, isEmpty);
      expect(queries, ['神之塔', ' 神之塔 ']);
      pending[1].complete(Res([searchComic('神之塔')]));
      await drain();
      expect(
        controller.bestMatches.single.best.relevance.tier,
        SearchRelevanceTier.exact,
      );
      controller.dispose();
    },
  );

  test(
    'source errors are isolated and successful response feeds both views only once',
    () async {
      var calls = 0;
      final comic = searchComic('神之塔', source: 'good');
      final good = provider('good', (_, page, _) async {
        calls++;
        expect(page, 1);
        return Res([comic], subData: 7);
      });
      final bad = provider(
        'bad',
        (_, _, _) async => const Res.error('broken provider'),
      );
      final thrown = provider(
        'thrown',
        (_, _, _) => throw StateError('broken runtime'),
      );
      final controller = AggregatedSearchController();
      controller.search('神之塔', [bad, good, thrown]);
      await drain();
      expect(controller.results[0].error, 'broken provider');
      expect(controller.results[2].error, contains('broken runtime'));
      expect(controller.bestMatches.single.best.comic, same(comic));
      expect(controller.results[1].comics.single, same(comic));
      expect(controller.results[1].pagination, 7);
      expect(calls, 1);
      expect(controller.pendingSources, 0);
      controller.dispose();
    },
  );

  test(
    'slow providers do not delay exact cards; interaction freezes targets until refresh',
    () async {
      final pending = Completer<Res<List<Comic>>>();
      final slow = provider('slow', (_, _, _) => pending.future);
      final fast = provider(
        'fast',
        (_, _, _) async => Res([searchComic('weak', source: 'fast')]),
      );
      final controller = AggregatedSearchController();
      controller.search('神之塔', [slow, fast]);
      await drain();
      expect(controller.pendingSources, 1);
      final visible = controller.bestMatches;
      controller.freezePlacement();
      pending.complete(Res([searchComic('神之塔', source: 'slow')]));
      await drain();
      expect(controller.bestMatches, same(visible));
      expect(controller.hasUpdatedMatches, isTrue);
      controller.refreshPlacement();
      expect(controller.bestMatches.first.best.comic.title, '神之塔');
      controller.dispose();
    },
  );

  test(
    'disposal retains running admission slot and ignores notifications',
    () async {
      final pending = Completer<Res<List<Comic>>>();
      var calls = 0;
      final p = provider('a', (_, _, _) {
        calls++;
        return calls == 1 ? pending.future : Future.value(const Res([]));
      });
      final admission = SearchOperationAdmission();
      final a = AggregatedSearchController(admission: admission);
      final b = AggregatedSearchController(admission: admission);
      a.search('old', [p]);
      a.dispose();
      b.search('new', [p]);
      expect(calls, 1);
      pending.complete(const Res([]));
      await drain();
      expect(calls, 2);
      expect(b.pendingSources, 0);
      b.dispose();
    },
  );

  test(
    'empty query starts no operations and cursor providers preserve null first cursor',
    () async {
      var calls = 0;
      final source = searchSource(
        'cursor',
        null,
        next: (q, cursor, _) async {
          calls++;
          expect(cursor, isNull);
          expect(q, 'Tower of God');
          return const Res([], subData: 'next');
        },
      );
      ComicSourceManager().add(source);
      registered.add('cursor');
      final controller = AggregatedSearchController();
      controller.search('  ', [SearchProvider(source)]);
      await drain();
      expect(calls, 0);
      expect(controller.pendingSources, 0);
      controller.search('Tower of God', [SearchProvider(source)]);
      await drain();
      expect(calls, 1);
      expect(controller.results.single.pagination, 'next');
      controller.dispose();
    },
  );

  test(
    'replacement artifact with same runtime key never receives old results',
    () async {
      final pending = Completer<Res<List<Comic>>>();
      final old = provider('a', (_, _, _) => pending.future);
      final controller = AggregatedSearchController();
      controller.search('q', [old]);
      ComicSourceManager().remove('a');
      final replacement = provider(
        'a',
        (_, _, _) async => Res([searchComic('replacement')]),
        version: '2.0.0',
      );
      controller.search('q', [replacement]);
      pending.complete(Res([searchComic('old')]));
      await drain();
      expect(controller.bestMatches.single.best.comic.title, 'replacement');
      expect(
        controller.bestMatches.single.best.artifact,
        same(replacement.source),
      );
      controller.dispose();
    },
  );

  test('Best Matches cap does not truncate provider shelves', () async {
    final p = provider(
      'a',
      (_, _, _) async =>
          Res(List.generate(1000, (i) => searchComic('weak $i'))),
    );
    final controller = AggregatedSearchController();
    controller.search('神之塔', [p]);
    await drain();
    expect(controller.bestMatches, hasLength(20));
    expect(controller.results.single.comics, hasLength(1000));
    controller.dispose();
  });
}
