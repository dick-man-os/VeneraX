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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
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

  group('Comicabc ComicSource QuickJS Runtime Validation', () {
    late ComicSource source;
    late Comic dynamicComic;
    String realEpId = '';

    test('1. Parses and instantiates comicabc.js via ComicSourceParser', () async {
      final jsPath = '../venera-configs/comicabc.js';
      final jsFile = File(jsPath);
      expect(jsFile.existsSync(), isTrue, reason: 'comicabc.js must exist at $jsPath');
      final jsContent = await jsFile.readAsString();

      source = await ComicSourceParser().parse(jsContent, jsFile.absolute.path);

      expect(source.key, equals('zh_Hant_comicabc'));
      expect(source.name, equals('Comicabc'));
      expect(source.version, equals('1.0.1'));
      expect(source.searchPageData, isNotNull);
      expect(source.loadComicInfo, isNotNull);
      expect(source.loadComicPages, isNotNull);
      expect(source.getThumbnailLoadingConfig, isNotNull);
      expect(source.getImageLoadingConfig, isNotNull);
    });

    test('2. Acquire real comic dynamically via Search & verify absolute thumbnail', () async {
      final searchRes = await source.searchPageData!.loadPage!('終結的熾天使', 1, <String>[]);
      expect(searchRes.error, isFalse, reason: 'Search error: ${searchRes.errorMessage}');
      expect(searchRes.data, isNotNull);
      expect(searchRes.data!, isNotEmpty);

      dynamicComic = searchRes.data!.first;
      expect(dynamicComic.title, isNotEmpty);
      expect(dynamicComic.id, isNotEmpty);
      expect(dynamicComic.cover, startsWith('http'));

      // Real thumbnail download via AppDio
      final thumbConfig = source.getThumbnailLoadingConfig!(dynamicComic.cover);
      expect(thumbConfig, isNotNull);
      final headers = thumbConfig['headers'] as Map?;

      final response = await AppDio().get<List<int>>(
        dynamicComic.cover,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers != null ? Map<String, dynamic>.from(headers) : null,
        ),
      );
      expect(response.statusCode, equals(200));
      expect(response.data, isNotNull);
      expect(response.data!.length, greaterThan(100));
      expect(response.headers.value('content-type'), contains('image/'));
    });

    test('3. Public loadComicInfo extracts real chapters without fallback', () async {
      expect(dynamicComic.id, isNotEmpty);

      final detailsRes = await source.loadComicInfo!(dynamicComic.id);
      expect(detailsRes.error, isFalse, reason: 'loadInfo error: ${detailsRes.errorMessage}');
      final details = detailsRes.data!;

      expect(details.title, isNotEmpty);
      expect(details.chapters, isNotNull);
      expect(details.chapters!.allChapters.length, greaterThan(0));

      final allChapters = details.chapters!.allChapters;
      final keys = allChapters.keys.toList();
      expect(keys, isNotEmpty);

      realEpId = keys.last;
      expect(realEpId, isNotEmpty);
      expect(realEpId, isNot(equals('dummy')));
      expect(realEpId, isNot(equals('/view/9154-1.html')));

      // Chapter sanitization check
      for (final entry in allChapters.entries) {
        expect(entry.key, isNotEmpty);
        expect(entry.value, isNotEmpty);
        expect(entry.value.contains('document.'), isFalse);
        expect(entry.value.contains('getElementById'), isFalse);
        expect(entry.value.contains('<script'), isFalse);
        expect(entry.value.contains('isnew('), isFalse);
      }
    });

    test('4. Public loadComicPages with real epId & Image Download', () async {
      expect(dynamicComic.id, isNotEmpty);
      expect(realEpId, isNotEmpty);

      final pagesRes = await source.loadComicPages!(dynamicComic.id, realEpId);
      expect(pagesRes.error, isFalse, reason: 'loadComicPages error: ${pagesRes.errorMessage}');
      expect(pagesRes.data, isNotNull);
      expect(pagesRes.data!, isNotEmpty);

      final firstImage = pagesRes.data!.first;
      expect(firstImage, startsWith('http'));

      final imageConfig = await source.getImageLoadingConfig!(firstImage, dynamicComic.id, realEpId);
      expect(imageConfig, isNotNull);
      final headers = imageConfig['headers'] as Map?;

      final response = await AppDio().get<List<int>>(
        firstImage,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers != null ? Map<String, dynamic>.from(headers) : null,
        ),
      );
      expect(response.statusCode, equals(200));
      expect(response.data, isNotNull);
      expect(response.data!.length, greaterThan(500));
      expect(response.headers.value('content-type'), contains('image/'));
    });
  });
}
