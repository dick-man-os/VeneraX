import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/search_page.dart';
import 'package:venera/pages/aggregated_search_page.dart';
import 'package:venera/pages/search_result_page.dart';
import 'package:venera/utils/translations.dart';

void main() {
  const sourceKey = 'search_history_test_source';

  late Directory tempDir;
  late String originalDataPath;
  late List<String> originalSearchHistory;
  late dynamic originalSearchSources;
  late dynamic originalDefaultSearchTarget;

  ComicSource buildSource() {
    return ComicSource(
      'Search history test',
      sourceKey,
      null,
      null,
      null,
      null,
      const [],
      SearchPageData(
        null,
        (keyword, page, options) async => const Res([]),
        null,
      ),
      null,
      null,
      null,
      null,
      null,
      null,
      'search_history_test.js',
      '',
      '1.0.0',
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      false,
      false,
      null,
      null,
    );
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppTranslation.init();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('venera-search-history-');
    originalDataPath = App.dataPath;
    originalSearchHistory = List<String>.from(appdata.searchHistory);
    originalSearchSources = appdata.settings['searchSources'];
    originalDefaultSearchTarget = appdata.settings['defaultSearchTarget'];
    App.dataPath = tempDir.path;
    appdata.searchHistory = ['A', 'B', 'C'];
    appdata.settings['searchSources'] = [sourceKey];
    appdata.settings['defaultSearchTarget'] = sourceKey;
    ComicSourceManager().add(buildSource());
  });

  tearDown(() async {
    await appdata.saveData(false);
    ComicSourceManager().remove(sourceKey);
    appdata.settings['searchSources'] = originalSearchSources;
    appdata.settings['defaultSearchTarget'] = originalDefaultSearchTarget;
    appdata.searchHistory = originalSearchHistory;
    App.dataPath = originalDataPath;
    await tempDir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> readSnapshot() async {
    return Map<String, dynamic>.from(
      jsonDecode(
        await File(
          '${tempDir.path}${Platform.pathSeparator}appdata.json',
        ).readAsString(),
      ),
    );
  }

  Future<void> waitForAppdataSave(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Drain any save that overlapped a prior unawaited UI-triggered save. This
    // runs outside FakeAsync so Appdata's 20 ms serialization wait cannot leave
    // a pending timer behind when the widget test is disposed.
    await tester.runAsync(() => appdata.saveData(false));
    await tester.pump();
  }

  testWidgets('delete removes only its row without triggering search', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Material(child: child),
        home: const SearchPage(),
      ),
    );
    await tester.pump();

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete').at(1));
    await tester.pump();
    await waitForAppdataSave(tester);

    expect(appdata.searchHistory, ['A', 'C']);
    final snapshot = await tester.runAsync(readSnapshot);
    expect(snapshot!['searchHistory'], ['A', 'C']);
    expect(find.text('B'), findsNothing);
    expect(find.byType(SearchResultPage), findsNothing);

    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultPage), findsOneWidget);
    await waitForAppdataSave(tester);

    Navigator.of(tester.element(find.byType(SearchResultPage))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete').first);
    await waitForAppdataSave(tester);
    await tester.tap(find.byTooltip('Delete').first);
    await waitForAppdataSave(tester);

    expect(appdata.searchHistory, isEmpty);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.text('Search History'), findsOneWidget);
    expect(find.byType(SearchResultPage), findsNothing);
  });

  testWidgets(
    'aggregate multilingual history click, single delete and clear all persist',
    (tester) async {
      appdata.settings['defaultSearchTarget'] = '_aggregated_';
      appdata.searchHistory = ['神之塔', 'Tower of God'];
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => Material(child: child),
          home: const SearchPage(),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Tower of God'));
      await waitForAppdataSave(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AggregatedSearchPage), findsOneWidget);
      expect(appdata.searchHistory, ['Tower of God', '神之塔']);
      Navigator.of(tester.element(find.byType(AggregatedSearchPage))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Delete').first);
      await tester.tap(find.byTooltip('Delete').first);
      await waitForAppdataSave(tester);
      expect(appdata.searchHistory, ['神之塔']);
      expect(find.byType(AggregatedSearchPage), findsNothing);
      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
      await tester.pumpAndSettle();
      await waitForAppdataSave(tester);
      expect(appdata.searchHistory, isEmpty);
      expect((await tester.runAsync(readSnapshot))!['searchHistory'], isEmpty);
    },
  );

  test(
    'single deletion and empty state persist through the existing store',
    () async {
      appdata.removeSearchHistory('B');
      await appdata.saveData(false);

      expect(appdata.searchHistory, ['A', 'C']);
      expect((await readSnapshot())['searchHistory'], ['A', 'C']);

      appdata.searchHistory = ['A'];
      appdata.removeSearchHistory('A');
      await appdata.saveData(false);

      expect(appdata.searchHistory, isEmpty);
      expect((await readSnapshot())['searchHistory'], isEmpty);
    },
  );
}
