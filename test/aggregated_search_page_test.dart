import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:venera/components/best_matches_section.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_details_cache.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/aggregated_search_page.dart';
import 'package:venera/pages/search_result_page.dart';
import 'package:venera/utils/translations.dart';
import 'helpers/search_fixture.dart';

void main() {
  late Directory directory;
  late String oldPath;
  late List<String> oldHistory;
  late dynamic oldSearchSources;
  late dynamic oldShowFavorite;
  late dynamic oldShowReadLater;
  late dynamic oldLanguage;
  final registered = <String>[];
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    if (Platform.isWindows) {
      open.overrideFor(
        OperatingSystem.windows,
        () => DynamicLibrary.open('winsqlite3.dll'),
      );
    }
    await AppTranslation.init();
  });
  setUp(() {
    directory = Directory.systemTemp.createTempSync('venera-best-matches-');
    oldPath = App.dataPath;
    App.dataPath = directory.path;
    oldHistory = List.of(appdata.searchHistory);
    oldSearchSources = appdata.settings['searchSources'];
    oldShowFavorite = appdata.settings['showFavoriteStatusOnTile'];
    oldShowReadLater = appdata.settings['showReadLaterStatusOnTile'];
    oldLanguage = appdata.settings['language'];
    appdata.settings['showFavoriteStatusOnTile'] = false;
    appdata.settings['showReadLaterStatusOnTile'] = false;
    appdata.settings['language'] = 'en-US';
  });
  tearDown(() async {
    await appdata.saveData(false);
    for (final key in registered) {
      ComicSourceManager().remove(key);
    }
    registered.clear();
    appdata.settings['searchSources'] = oldSearchSources;
    appdata.settings['showFavoriteStatusOnTile'] = oldShowFavorite;
    appdata.settings['showReadLaterStatusOnTile'] = oldShowReadLater;
    appdata.settings['language'] = oldLanguage;
    appdata.searchHistory = oldHistory;
    // Detail navigation may have opened this existing device-local cache.
    if (File('${directory.path}/details_cache.db').existsSync()) {
      ComicDetailsCache().close();
    }
    App.dataPath = oldPath;
    directory.deleteSync(recursive: true);
  });
  void register(ComicSource source) {
    ComicSourceManager().add(source);
    registered.add(source.key);
    appdata.settings['searchSources'] = List.of(registered);
  }

  Future<void> mount(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => Material(child: child),
        home: page,
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> save(WidgetTester tester) async {
    await settle(tester);
    await tester.runAsync(() => appdata.saveData(false));
    await tester.pump();
  }

  testWidgets(
    'one response renders ranked Best Matches and unchanged shelf order',
    (tester) async {
      var calls = 0;
      var detailCalls = 0;
      register(
        searchSource(
          'a',
          (q, _, _) async {
            calls++;
            expect(q, '神之塔');
            return Res([searchComic('weak'), searchComic('神之塔')]);
          },
          detail: (_) async {
            detailCalls++;
            return const Res.error('unused');
          },
        ),
      );
      await mount(tester, const AggregatedSearchPage(keyword: '神之塔'));
      await settle(tester);
      expect(find.text('Best Matches'), findsOneWidget);
      expect(find.text('Results by Source'), findsOneWidget);
      final section = tester.widget<BestMatchesSection>(
        find.byType(BestMatchesSection),
      );
      expect(section.controller.bestMatches.map((g) => g.best.comic.title), [
        '神之塔',
        'weak',
      ]);
      expect(section.controller.results.single.comics.map((c) => c.title), [
        'weak',
        '神之塔',
      ]);
      expect(calls, 1);
      expect(detailCalls, 0);
      expect(find.text('weak'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await save(tester);
    },
  );

  testWidgets(
    'typing a new query cannot display old results and keeps multilingual history',
    (tester) async {
      final first = Completer<Res<List<Comic>>>();
      final second = Completer<Res<List<Comic>>>();
      final queries = <String>[];
      register(
        searchSource('a', (q, _, _) {
          queries.add(q);
          return queries.length == 1 ? first.future : second.future;
        }),
      );
      await mount(tester, const AggregatedSearchPage(keyword: '神之塔'));
      await tester.enterText(find.byType(EditableText).first, 'Tower of God');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      first.complete(Res([searchComic('STALE')]));
      await tester.pump();
      expect(find.text('STALE'), findsNothing);
      expect(queries, ['神之塔', 'Tower of God']);
      second.complete(Res([searchComic('Tower of God')]));
      await settle(tester);
      expect(appdata.searchHistory.take(2), ['Tower of God', '神之塔']);
      expect(find.text('STALE'), findsNothing);
      await save(tester);
    },
  );

  testWidgets(
    'Best Match detail route and Back retain query/results without another search',
    (tester) async {
      var calls = 0;
      register(
        searchSource('a', (q, _, _) async {
          calls++;
          return Res([searchComic('神之塔', id: 'own-id')]);
        }),
      );
      await mount(tester, const AggregatedSearchPage(keyword: '神之塔'));
      await settle(tester);
      final before = tester
          .widget<BestMatchesSection>(find.byType(BestMatchesSection))
          .controller;
      await tester.tap(find.byType(ActionChip).first);
      final navigator = Navigator.of(
        tester.element(find.byType(AggregatedSearchPage)),
      );
      expect(navigator.canPop(), isTrue);
      navigator.pop();
      await settle(tester);
      final after = tester
          .widget<BestMatchesSection>(find.byType(BestMatchesSection))
          .controller;
      expect(after, same(before));
      expect(after.query, '神之塔');
      expect(after.bestMatches.single.best.comic.id, 'own-id');
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      await save(tester);
    },
  );

  testWidgets(
    'empty aggregate starts no search; selected single-source UI has no Best Matches',
    (tester) async {
      var calls = 0;
      register(
        searchSource('a', (q, _, _) async {
          calls++;
          return const Res([]);
        }),
      );
      await mount(tester, const AggregatedSearchPage(keyword: '  '));
      expect(calls, 0);
      expect(find.byType(BestMatchesSection), findsNothing);
      await mount(
        tester,
        const SearchResultPage(text: 'Tower of God', sourceKey: 'a'),
      );
      await settle(tester);
      expect(calls, 1);
      expect(find.byType(BestMatchesSection), findsNothing);
      await save(tester);
    },
  );

  testWidgets(
    'Chinese labels and source failure remain visible without hiding successful results',
    (tester) async {
      appdata.settings['language'] = 'zh-TW';
      register(searchSource('a', (_, _, _) async => Res([searchComic('神之塔')])));
      register(
        searchSource(
          'b',
          (_, _, _) async => const Res.error('CloudflareException: blocked'),
        ),
      );
      await mount(tester, const AggregatedSearchPage(keyword: '神之塔'));
      await settle(tester);
      expect(find.text('最佳符合'), findsOneWidget);
      expect(find.text('各來源結果'), findsOneWidget);
      final section = tester.widget<BestMatchesSection>(
        find.byType(BestMatchesSection),
      );
      expect(section.controller.bestMatches.single.best.comic.title, '神之塔');
      expect(
        section.controller.results[1].error,
        contains('CloudflareException'),
      );
      await save(tester);
    },
  );
}
