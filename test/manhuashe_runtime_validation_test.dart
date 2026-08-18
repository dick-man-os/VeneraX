import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
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

  group('Manhuashe ComicSource QuickJS Runtime Validation', () {
    late ComicSource source;
    String firstComicId = '';
    String firstChapterId = '';

    test('1. Parses and instantiates manhuashe.js via ComicSourceParser', () async {
      final jsPath = '../venera-configs/manhuashe.js';
      final jsFile = File(jsPath);
      expect(jsFile.existsSync(), isTrue, reason: 'manhuashe.js must exist at $jsPath');
      final jsContent = await jsFile.readAsString();

      // Simulate full app initialization for sources
      final sourceDir = Directory('${App.dataPath}/comic_source');
      if (!sourceDir.existsSync()) {
        sourceDir.createSync(recursive: true);
      }
      File('${sourceDir.path}/manhuashe.js').writeAsStringSync(jsContent);

      await ComicSourceManager().init();

      source = ComicSourceManager().find('zh_Hans_manhuashe')!;

      expect(source.key, equals('zh_Hans_manhuashe'));
      expect(source.name, equals('Manhuashe'));
      expect(source.explorePages, isNotEmpty);
      expect(source.searchPageData, isNotNull);
      expect(source.loadComicInfo, isNotNull);
      expect(source.loadComicPages, isNotNull);

      // Default mirror verification
      source.data["settings"] ??= <String, dynamic>{};
      source.data["settings"]["baseUrlSelection"] = 'https://www.311s.com';
    });

    test('2. Explore Popular loads ranking list', () async {
      final popularExplore = source.explorePages.firstWhere((e) => e.title == 'Popular');
      final res = await popularExplore.loadPage!(1);
      expect(res.error, isFalse, reason: 'Explore Popular error: ${res.errorMessage}');
      expect(res.data, isNotEmpty);
      final first = res.data!.first;
      expect(first.title, isNotEmpty);
      expect(first.id, isNotEmpty);
      expect(first.cover, isNotEmpty);
      firstComicId = first.id;
      print('Explore Popular first item: ${first.title} (${first.id})');
    });

    test('3. Explore Latest loads', () async {
      final latestExplore = source.explorePages.firstWhere((e) => e.title == 'Latest');
      final res = await latestExplore.loadPage!(1);
      expect(res.error, isFalse, reason: 'Explore Latest error: ${res.errorMessage}');
      expect(res.data, isNotEmpty);
      final first = res.data!.first;
      expect(first.title, isNotEmpty);
      expect(first.id, isNotEmpty);
      print('Explore Latest first item: ${first.title} (${first.id})');
    });

    test('4. Search queries keyword and returns matching comics', () async {
      final searchRes = await source.searchPageData!.loadPage!('一人', 1, <String>[]);
      expect(searchRes.error, isFalse, reason: 'Search error: ${searchRes.errorMessage}');
      expect(searchRes.data, isNotEmpty);
      final match = searchRes.data!.first;
      expect(match.title, isNotEmpty);
      expect(match.id, isNotEmpty);
      print('Search match: ${match.title} -> ${match.id}');
    });

    test('5. Comic details and chapter list parsing (loadInfo)', () async {
      final detailsRes = await source.loadComicInfo!(firstComicId);
      expect(detailsRes.error, isFalse, reason: 'loadInfo error: ${detailsRes.errorMessage}');
      final details = detailsRes.data!;
      expect(details.title, isNotEmpty);
      expect(details.subTitle, isNotEmpty, reason: 'Patched author should exist');
      expect(details.cover, isNotEmpty);
      expect(details.tags, isNotEmpty, reason: 'Patched tags should exist');
      expect(details.chapters, isNotNull);

      final allChapters = details.chapters!.allChapters;
      expect(allChapters, isNotEmpty);
      print('Comic Details: ${details.title}, Author: ${details.subTitle}, Tags: ${details.tags}, Chapters: ${allChapters.length}');

      final firstMappedKey = allChapters.keys.first;
      final firstMappedTitle = allChapters[firstMappedKey];
      final lastMappedKey = allChapters.keys.last;
      final lastMappedTitle = allChapters[lastMappedKey];
      print('First in map: $firstMappedTitle -> $firstMappedKey');
      print('Last in map: $lastMappedTitle -> $lastMappedKey');

      // Select the oldest chapter
      firstChapterId = lastMappedKey;
    });

    test('6. Episode pages loading (loadEp) & Image Download via AppDio', () async {
      final pagesRes = await source.loadComicPages!(firstComicId, firstChapterId);
      expect(pagesRes.error, isFalse, reason: 'loadEp error: ${pagesRes.errorMessage}');
      expect(pagesRes.data, isNotEmpty);
      final firstImage = pagesRes.data!.first;
      expect(firstImage, startsWith('http'));
      print('First Image URL: $firstImage');

      final imageConfig = await source.getImageLoadingConfig!(firstImage, firstComicId, firstChapterId);
      final headers = (imageConfig as Map)['headers'] as Map?;
      expect(headers!['Referer'], contains('311s.com'), reason: 'Referer must match primary mirror');

      final response = await AppDio().get<List<int>>(
        firstImage,
        options: Options(
          responseType: ResponseType.bytes,
          headers: Map<String, dynamic>.from(headers),
        ),
      );
      expect(response.statusCode, equals(200));
      expect(response.data!.length, greaterThan(1000));
      print('Reader Image Download SUCCESS: ${response.data!.length} bytes');
    });

    test('7. Secondary mirror setting', () async {
       source.data["settings"] ??= <String, dynamic>{};
       source.data["settings"]["baseUrlSelection"] = 'https://www.m206.com';

       final popularExplore = source.explorePages.firstWhere((e) => e.title == 'Popular');
       final res = await popularExplore.loadPage!(1);
       expect(res.error, isFalse, reason: 'Explore Popular on secondary mirror error: ${res.errorMessage}');
       expect(res.data, isNotEmpty);
       print('Secondary mirror loaded ${res.data!.length} comics successfully.');

       appdata.settings['source_baseUrlSelection_${source.key}'] = 'https://www.311s.com';
    });
  });
}
