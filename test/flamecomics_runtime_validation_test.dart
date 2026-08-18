import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/network/app_dio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    final tempDir = Directory.systemTemp.createTempSync('venerax_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider_windows'),
      (MethodCall methodCall) async => tempDir.path,
    );

    PackageInfo.setMockInitialValues(
      appName: 'VeneraX',
      packageName: 'com.venera.app',
      version: '1.6.0',
      buildNumber: '1',
      buildSignature: '',
    );

    await App.init();
    App.dataPath = tempDir.path;
    App.cachePath = tempDir.path;

    final initJsFile = File('assets/init.js');
    if (initJsFile.existsSync()) {
      JsEngine.cacheJsInit(initJsFile.readAsBytesSync());
    }
    await JsEngine().init();
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('Flame Comics ComicSource QuickJS Runtime Validation', () {
    late ComicSource source;
    String sampleComicId = '';
    String sampleEpId = '';

    test('1. Parses and instantiates flamecomics.js via ComicSourceParser', () async {
      final jsPath = '../venera-configs/flamecomics.js';
      final jsFile = File(jsPath);
      expect(jsFile.existsSync(), isTrue, reason: 'flamecomics.js must exist at $jsPath');
      final jsContent = await jsFile.readAsString();

      source = await ComicSourceParser().parse(jsContent, jsFile.absolute.path);

      expect(source.key, equals('en_flamecomics'));
      expect(source.name, equals('Flame Comics'));
      expect(source.version, equals('1.0.1'));
      expect(source.explorePages, isNotEmpty);
      expect(source.searchPageData, isNotNull);
      expect(source.searchPageData!.loadPage, isNotNull);
      expect(source.loadComicInfo, isNotNull);
      expect(source.loadComicPages, isNotNull);
      expect(source.getImageLoadingConfig, isNotNull);
      expect(source.getThumbnailLoadingConfig, isNotNull);
    });

    test('2. Explore Popular loads ranking list', () async {
      final popularExplore = source.explorePages.firstWhere((e) => e.title == 'Popular');
      expect(popularExplore.loadPage, isNotNull);
      final res = await popularExplore.loadPage!(1);
      expect(res.error, isFalse, reason: 'Explore Popular error: ${res.errorMessage}');
      expect(res.data, isNotEmpty);
      final first = res.data!.first;
      expect(first.title, isNotEmpty);
      expect(first.id, isNotEmpty);
      expect(first.cover, startsWith('http'));
      sampleComicId = first.id;
    });

    test('3. Explore Latest loads latest entries', () async {
      final latestExplore = source.explorePages.firstWhere((e) => e.title == 'Latest');
      expect(latestExplore.loadPage, isNotNull);
      final res = await latestExplore.loadPage!(1);
      expect(res.error, isFalse, reason: 'Explore Latest error: ${res.errorMessage}');
      expect(res.data, isNotEmpty);
      final first = res.data!.first;
      expect(first.title, isNotEmpty);
      expect(first.id, isNotEmpty);
      expect(first.cover, startsWith('http'));
    });

    test('4. Search queries keyword and returns matching comics', () async {
      final searchRes = await source.searchPageData!.loadPage!('solo', 1, <String>[]);
      expect(searchRes.error, isFalse, reason: 'Search error: ${searchRes.errorMessage}');
      expect(searchRes.data, isNotEmpty);
      final match = searchRes.data!.first;
      expect(match.title, isNotEmpty);
      expect(match.id, isNotEmpty);
    });

    test('5. Comic details and chapter list parsing (loadInfo)', () async {
      expect(sampleComicId, isNotEmpty, reason: 'Must obtain dynamic comic ID from Explore/Search');
      final detailsRes = await source.loadComicInfo!(sampleComicId);
      expect(detailsRes.error, isFalse, reason: 'loadInfo error: ${detailsRes.errorMessage}');
      final details = detailsRes.data!;

      expect(details.title, isNotEmpty);
      expect(details.subTitle, isNotNull);
      expect(details.chapters, isNotNull);
      expect(details.chapters!.allChapters.length, greaterThan(0));

      final allChapters = details.chapters!.allChapters;
      final keys = allChapters.keys.toList();
      sampleEpId = keys.last;
      expect(sampleEpId, isNotEmpty, reason: 'Must extract real epId from returned chapter map');
    });

    test('6. Episode pages loading (loadEp) & Image Download via AppDio', () async {
      expect(sampleComicId, isNotEmpty, reason: 'Must have dynamic comic ID');
      expect(sampleEpId, isNotEmpty, reason: 'Must have dynamic epId from loadInfo');

      final pagesRes = await source.loadComicPages!(sampleComicId, sampleEpId);
      expect(pagesRes.error, isFalse, reason: 'loadEp error: ${pagesRes.errorMessage}');
      expect(pagesRes.data, isNotEmpty);

      final firstImage = pagesRes.data!.first;
      expect(firstImage, startsWith('https://cdn.flamecomics.xyz'));

      final imageConfig = await source.getImageLoadingConfig!(firstImage, sampleComicId, sampleEpId);
      expect(imageConfig, isNotNull);
      final headers = (imageConfig as Map)['headers'] as Map?;
      expect(headers, isNotNull);
      expect(headers!['Referer'], contains('flamecomics.xyz'));

      final response = await AppDio().get<List<int>>(
        firstImage,
        options: Options(
          responseType: ResponseType.bytes,
          headers: Map<String, dynamic>.from(headers),
        ),
      );
      expect(response.statusCode, equals(200));
      expect(response.data, isNotNull);
      expect(response.data!.length, greaterThan(500));
      expect(response.headers.value('content-type'), contains('image/'));
    });

    test('7. BuildId auto-refresh resilience on stale / 404', () async {
      final buildIdRes = await JsEngine().runCode("""
        ComicSource.sources.en_flamecomics.getBuildId()
      """);
      expect(buildIdRes, isNotNull);
      expect(buildIdRes.toString(), isNotEmpty);

      // Invalidate buildId in JS engine to test auto-refresh
      await JsEngine().runCode("""
        ComicSource.sources.en_flamecomics._buildId = 'invalid-stale-build-id';
      """);

      // Verify fetchNextApi detects stale/invalid buildId and auto-refreshes
      final freshData = await JsEngine().runCode("""
        ComicSource.sources.en_flamecomics.fetchNextApi('index.json')
      """);
      expect(freshData, isNotNull);
      final restoredBuildId = await JsEngine().runCode("""
        ComicSource.sources.en_flamecomics._buildId
      """);
      expect(restoredBuildId, isNot(equals('invalid-stale-build-id')));
    });
  });
}
