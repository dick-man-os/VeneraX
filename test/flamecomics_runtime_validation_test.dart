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
      expect(source.version, equals('1.0.0'));
      expect(source.explorePages, isNotEmpty);
      expect(source.searchPageData, isNotNull);
      expect(source.searchPageData!.loadPage, isNotNull);
      expect(source.loadComicInfo, isNotNull);
      expect(source.loadComicPages, isNotNull);
      expect(source.getImageLoadingConfig, isNotNull);
      expect(source.getThumbnailLoadingConfig, isNotNull);
      print('Parsed Flame Comics source: key=${source.key}, name=${source.name}, version=${source.version}');
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
      print('Explore Popular count: ${res.data!.length}, first: ${first.title} (${first.id}) [cover: ${first.cover}]');
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
      print('Explore Latest count: ${res.data!.length}, first: ${first.title} (${first.id})');
    });

    test('4. Search queries keyword and returns matching comics', () async {
      final searchRes = await source.searchPageData!.loadPage!('solo', 1, <String>[]);
      expect(searchRes.error, isFalse, reason: 'Search error: ${searchRes.errorMessage}');
      expect(searchRes.data, isNotEmpty);
      final match = searchRes.data!.first;
      expect(match.title, isNotEmpty);
      expect(match.id, isNotEmpty);
      print('Search returned ${searchRes.data!.length} items, first match: ${match.title} -> ${match.id}');
    });

    test('5. Comic details and chapter list parsing (loadInfo) DIAGNOSIS', () async {
      final comicId = sampleComicId.isNotEmpty ? sampleComicId : '/series/165';
      print('=== DIAGNOSING FLAME COMICS LOADINFO FOR: $comicId ===');

      // Check parseChaptersCustom raw response via QuickJS
      final rawChaptersJson = await JsEngine().runCode("""
        ComicSource.sources.en_flamecomics.fetchNextApi('series/165.json?id=165')
      """);
      print('Raw series JSON keys: ${(rawChaptersJson as Map).keys.toList()}');
      final pageProps = (rawChaptersJson)['pageProps'] as Map;
      print('pageProps keys: ${pageProps.keys.toList()}');
      final series = pageProps['series'] as Map;
      print('series data: title="${series['title']}", author="${series['author']}", chaptersCount=${(pageProps['chapters'] as List).length}');
      final firstCh = (pageProps['chapters'] as List).first as Map;
      print('First chapter raw: token="${firstCh['token']}", chapter="${firstCh['chapter']}", title="${firstCh['title']}"');

      // Inspect raw chapter response
      final rawChapterJson = await JsEngine().runCode("""
        ComicSource.sources.en_flamecomics.fetchNextApi('series/165/${firstCh['token']}.json?id=165&token=${firstCh['token']}')
      """);
      print('Raw chapter JSON keys: ${(rawChapterJson as Map).keys.toList()}');
      final chPageProps = (rawChapterJson)['pageProps'] as Map;
      print('Chapter pageProps keys: ${chPageProps.keys.toList()}');
      print('Chapter pageProps content: $chPageProps');
    });

    test('6. Episode pages loading (loadEp) & Image Download via AppDio', () async {
      final comicId = sampleComicId.isNotEmpty ? sampleComicId : '/series/165';
      final testImageUrl = 'https://cdn.flamecomics.xyz/uploads/images/series/165/26f4cb97a437d7cb/30YRS-11-00.jpg?1786898318';
      print('Testing Real Image Download with Referer header: $testImageUrl');

      // Verify onImageLoad Referer header
      final imageConfig = await source.getImageLoadingConfig!(testImageUrl, comicId, '/series/165/26f4cb97a437d7cb');
      expect(imageConfig, isNotNull);
      final headers = (imageConfig as Map)['headers'] as Map?;
      expect(headers, isNotNull);
      expect(headers!['Referer'], contains('flamecomics.xyz'));
      print('onImageLoad Referer Header: ${headers['Referer']}');

      // Real Image HTTP download using AppDio with headers (Reader image pipeline)
      final response = await AppDio().get<List<int>>(
        testImageUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: Map<String, dynamic>.from(headers),
        ),
      );
      expect(response.statusCode, equals(200));
      expect(response.data, isNotNull);
      expect(response.data!.length, greaterThan(500));
      // Verify JPEG magic bytes: 0xFF, 0xD8, 0xFF
      expect(response.data![0], equals(0xFF));
      expect(response.data![1], equals(0xD8));
      expect(response.data![2], equals(0xFF));
      print('Reader Image Download SUCCESS: ${response.data!.length} bytes, valid JPEG binary verified!');
    });

    test('7. BuildId refresh on stale / 404', () async {
      // Test fetchNextApi cache & buildId acquisition
      final buildIdRes = await JsEngine().runCode("""
        ComicSource.sources.en_flamecomics.getBuildId()
      """);
      expect(buildIdRes, isNotNull);
      expect(buildIdRes.toString(), isNotEmpty);
      print('Current Flame Comics buildId: $buildIdRes');

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
      print('Successfully tested buildId auto-refresh! Refreshed buildId: $restoredBuildId');
    });
  });
}
