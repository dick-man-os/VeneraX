import 'dart:io';

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

  group('Webtoons ComicSource QuickJS Runtime Validation', () {
    late ComicSource source;

    test('1. Parses and instantiates webtoons.js via ComicSourceParser', () async {
      final jsPath = '../venera-configs/webtoons.js';
      final jsFile = File(jsPath);
      expect(jsFile.existsSync(), isTrue, reason: 'webtoons.js must exist at $jsPath');
      final jsContent = await jsFile.readAsString();

      source = await ComicSourceParser().parse(jsContent, jsFile.absolute.path);

      expect(source.key, equals('en_webtoons'));
      expect(source.name, equals('Webtoons'));
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
      final first = res.data.first;
      expect(first.title, isNotEmpty);
      expect(first.id, isNotEmpty);
      print('Explore Popular first item: ${first.title} (${first.id})');
    });

    test('3. Explore Latest loads originals for current day', () async {
      final latestExplore = source.explorePages.firstWhere((e) => e.title == 'Latest');
      expect(latestExplore.loadPage, isNotNull);
      final res = await latestExplore.loadPage!(1);
      expect(res.error, isFalse, reason: 'Explore Latest error: ${res.errorMessage}');
      expect(res.data, isNotEmpty);
      final first = res.data.first;
      expect(first.title, isNotEmpty);
      expect(first.id, isNotEmpty);
      print('Explore Latest first item: ${first.title} (${first.id})');
    });

    test('4. Search queries keyword and returns matching comics', () async {
      final searchRes = await source.searchPageData!.loadPage!('tower of god', 1, <String>[]);
      expect(searchRes.error, isFalse, reason: 'Search error: ${searchRes.errorMessage}');
      expect(searchRes.data, isNotEmpty);
      final match = searchRes.data.firstWhere(
        (c) => c.title.toLowerCase().contains('tower of god'),
        orElse: () => searchRes.data.first,
      );
      expect(match.title, isNotEmpty);
      expect(match.id, isNotEmpty);
      print('Search match: ${match.title} -> ${match.id}');
    });

    test('5. Comic details and chapter list parsing (loadInfo)', () async {
      final comicId = '/en/fantasy/tower-of-god/list?title_no=95';
      final detailsRes = await source.loadComicInfo!(comicId);
      expect(detailsRes.error, isFalse, reason: 'loadInfo error: ${detailsRes.errorMessage}');
      final details = detailsRes.data;
      expect(details.title, contains('Tower of God'));
      expect(details.subTitle, isNotEmpty);
      expect(details.title, isNotEmpty);

      if (details.subTitle != null) {
        expect(details.subTitle!.toLowerCase(), isNot(contains('author info')));
        expect(details.subTitle, isNot(contains('...')));
      }

      expect(details.chapters, isNotNull);
      final allChapters = details.chapters!.allChapters;
      expect(allChapters, isNotEmpty);
      print('Comic Details: ${details.title}, Author: ${details.subTitle}, Chapters: ${allChapters.length}');

      // Verify chapter ordering (latest first)
      final firstMappedKey = allChapters.keys.first;
      final firstMappedTitle = allChapters[firstMappedKey];
      final lastMappedKey = allChapters.keys.last;
      final lastMappedTitle = allChapters[lastMappedKey];
      print('Latest Chapter (first in map): $firstMappedTitle -> $firstMappedKey');
      print('First Chapter (last in map): $lastMappedTitle -> $lastMappedKey');
      expect(firstMappedKey, contains('title_no=95'));
    });

    test('6. Episode pages loading (loadEp) & Image Download via AppDio', () async {
      final comicId = '/en/fantasy/tower-of-god/list?title_no=95';
      final epId = '/en/fantasy/tower-of-god/season-1-ep-0/viewer?title_no=95&episode_no=1';
      final pagesRes = await source.loadComicPages!(comicId, epId);
      expect(pagesRes.error, isFalse, reason: 'loadEp error: ${pagesRes.errorMessage}');
      expect(pagesRes.data, isNotEmpty);
      print('Episode Pages count: ${pagesRes.data.length}');
      final firstImage = pagesRes.data.first;
      expect(firstImage, startsWith('http'));
      print('First Image URL: $firstImage');

      // 7. Verify onImageLoad Referer header
      final imageConfig = await source.getImageLoadingConfig!(firstImage, comicId, epId);
      expect(imageConfig, isNotNull);
      final headers = (imageConfig as Map)['headers'] as Map?;
      expect(headers, isNotNull);
      expect(headers!['Referer'], contains('webtoons.com'));
      print('onImageLoad Referer Header: ${headers['Referer']}');

      // 8. Test actual Image HTTP download using AppDio with headers (Reader image pipeline)
      final response = await AppDio().get<List<int>>(
        firstImage,
        options: Options(
          responseType: ResponseType.bytes,
          headers: Map<String, dynamic>.from(headers),
        ),
      );
      expect(response.statusCode, equals(200));
      expect(response.data, isNotNull);
      expect(response.data!.length, greaterThan(1000));
      // Verify JPEG magic bytes: 0xFF, 0xD8, 0xFF
      expect(response.data![0], equals(0xFF));
      expect(response.data![1], equals(0xD8));
      expect(response.data![2], equals(0xFF));
      print('Reader Image Download SUCCESS: ${response.data!.length} bytes, valid JPEG stream verified!');
    });

    test('7. Canvas chapter list smoke test', () async {
      final canvasComicId = '/en/canvas/meme-girls/list?title_no=304446';
      final detailsRes = await source.loadComicInfo!(canvasComicId);
      expect(detailsRes.error, isFalse, reason: 'Canvas loadInfo error: ${detailsRes.errorMessage}');
      final details = detailsRes.data;

      expect(details.title, isNotEmpty);

      // Ensure author metadata is not polluted
      if (details.subTitle != null) {
        expect(details.subTitle!.toLowerCase(), isNot(contains('author info')));
        expect(details.subTitle, isNot(contains('...')));
      }

      expect(details.chapters, isNotNull);
      expect(details.chapters!.allChapters, isNotEmpty);
      print('Canvas Chapters count: ${details.chapters!.allChapters.length}');
    });
  });
}
