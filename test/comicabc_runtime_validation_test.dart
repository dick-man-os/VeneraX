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

  group('Comicabc ComicSource QuickJS Runtime Validation', () {
    late ComicSource source;
    String firstComicId = '';
    String firstChapterId = '';

    test('1. Parses and instantiates comicabc.js via ComicSourceParser', () async {
      final jsPath = '../venera-configs/comicabc.js';
      final jsFile = File(jsPath);
      expect(jsFile.existsSync(), isTrue, reason: 'comicabc.js must exist at \$jsPath');
      final jsContent = await jsFile.readAsString();

      source = await ComicSourceParser().parse(jsContent, jsFile.absolute.path);

      expect(source.key, equals('zh_Hant_comicabc'));
      expect(source.name, equals('Comicabc'));
      expect(source.explorePages, isNotEmpty);
      expect(source.searchPageData, isNotNull);
      expect(source.loadComicInfo, isNotNull);
      expect(source.loadComicPages, isNotNull);
    });

    test('2. Explore Popular loads ranking list DIAGNOSIS', () async {
      print('=== POPULAR EXTERNAL APPDIO ===');
      final popUrl = 'https://www.8comic.com/comic/h-1.html';
      final dioRes = await AppDio().get(popUrl);
      final bodyStr = dioRes.data.toString();
      print('Pop Status: ${dioRes.statusCode}');
      print('Pop length: ${bodyStr.length}');
      print('Pop contains comicpic_col6: ${bodyStr.contains("comicpic_col6")}');
      print('Pop contains .container: ${bodyStr.contains("container")}');

      final popularExplore = source.explorePages.firstWhere((e) => e.title == 'Popular');
      expect(popularExplore.loadPage, isNotNull);
      final res = await popularExplore.loadPage!(1);
      expect(res.error, isFalse, reason: 'Explore Popular error: ${res.errorMessage}');
      print('Popular returned: ${res.data?.length}');
    });

    test('3. Explore Latest loads DIAGNOSIS', () async {
      print('=== LATEST EXTERNAL APPDIO ===');
      final latUrl = 'https://www.8comic.com/comic/u-1.html';
      final dioRes = await AppDio().get(latUrl);
      final bodyStr = dioRes.data.toString();
      print('Lat Status: ${dioRes.statusCode}');
      print('Lat length: ${bodyStr.length}');
      print('Lat contains cat2_list: ${bodyStr.contains("cat2_list")}');

      final latestExplore = source.explorePages.firstWhere((e) => e.title == 'Latest');
      expect(latestExplore.loadPage, isNotNull);
      final res = await latestExplore.loadPage!(1);
      expect(res.error, isFalse, reason: 'Explore Latest error: ${res.errorMessage}');
      print('Latest returned: ${res.data?.length}');
    });

    test('4. Search queries keyword and returns matching comics', () async {
      final searchRes = await source.searchPageData!.loadPage!('終結的熾天使', 1, <String>[]);
      expect(searchRes.error, isFalse, reason: 'Search error: ${searchRes.errorMessage}');
      expect(searchRes.data, isNotEmpty);
      final match = searchRes.data!.first;
      expect(match.title, isNotEmpty);
      expect(match.id, isNotEmpty);
      expect(match.cover, isNotEmpty);
      expect(match.id, isNot(equals('dummy')));
      print('Search match: ${match.title} -> ${match.id}');
    });

    test('5. Comic details and chapter list parsing (loadInfo) DIAGNOSIS', () async {
      // 9154 is Seraph of the End (終結的熾天使)
      final comicId = 'https://www.8comic.com/html/9154.html';

      print('=== DETAILS EXTERNAL APPDIO ===');
      final dioRes = await AppDio().get(comicId);
      final bodyStr = dioRes.data.toString();
      print('Status: ${dioRes.statusCode}');
      print('Body length: ${bodyStr.length}');
      print('Contains item_content_box: ${bodyStr.contains("item_content_box")}');
      print('Contains .h2: ${bodyStr.contains("h2")}');
      print('First 500 chars: ${bodyStr.substring(0, bodyStr.length > 500 ? 500 : bodyStr.length)}');

      final detailsRes = await source.loadComicInfo!(comicId);
      expect(detailsRes.error, isFalse, reason: 'loadInfo error: ${detailsRes.errorMessage}');
      final details = detailsRes.data!;

      print('Comic Details: ${details.title}, Author: ${details.subTitle}, Chapters: ${details.chapters?.allChapters.length ?? 0}');

      if (details.chapters != null && details.chapters!.allChapters.isNotEmpty) {
        final allChapters = details.chapters!.allChapters;
        final keys = allChapters.keys.toList();
        firstChapterId = keys.last;
      } else {
        // Mock a chapter ID to allow test 6 diagnosis to proceed
        firstChapterId = '/view/9154-1.html';
      }
    });

    test('6. Episode pages loading (loadEp) DIAGNOSIS', () async {
      final comicId = 'https://www.8comic.com/html/9154.html';
      final epUrl = firstChapterId.startsWith('http') ? firstChapterId : 'https://www.8comic.com$firstChapterId';

      print('=== LOAD EP EXTERNAL APPDIO ===');
      print('GET $epUrl');
      final dioRes = await AppDio().get(
        epUrl,
        options: Options(headers: {'Referer': 'https://www.8comic.com/'})
      );
      final bodyStr = dioRes.data.toString();
      print('Ep URL: $epUrl');
      print('Status: ${dioRes.statusCode}');
      print('Body length: ${bodyStr.length}');
      print('Contains comics-pics: ${bodyStr.contains("comics-pics")}');
      print('Contains WordPress: ${bodyStr.contains("WordPress")}');
      print('Contains Cloudflare: ${bodyStr.contains("Cloudflare")}');
      print('First 500 chars: ${bodyStr.substring(0, bodyStr.length > 500 ? 500 : bodyStr.length)}');

      try {
        final pagesRes = await source.loadComicPages!(comicId, firstChapterId);
        print('loadEp res: ${pagesRes.data?.length}');
      } catch (e) {
        print('loadEp exception: $e');
      }
    });

    test('7. Episode pages loading (loadEp) & Image Download via AppDio', () async {
      // Use 9154 firstChapterId (ch=1)
      final comicId = 'https://articles.onemoreplace.tw/online/new-9154.html';
      final pagesRes = await source.loadComicPages!(comicId, firstChapterId);
      expect(pagesRes.error, isFalse, reason: 'loadEp error: \${pagesRes.errorMessage}');
      expect(pagesRes.data, isNotEmpty);
      print('Episode Pages count: \${pagesRes.data!.length}');
      final firstImage = pagesRes.data!.first;
      final lastImage = pagesRes.data!.last;
      expect(firstImage, startsWith('http'));
      print('First Image URL: \$firstImage');
      print('Last Image URL: \$lastImage');

      // 7. Verify onImageLoad Referer header
      final imageConfig = await source.getImageLoadingConfig!(firstImage, comicId, firstChapterId);
      expect(imageConfig, isNotNull);
      final headers = (imageConfig as Map)['headers'] as Map?;
      expect(headers, isNotNull);
      expect(headers!['Referer'], contains('articles.onemoreplace.tw'));
      print('onImageLoad Referer Header: \${headers["Referer"]}');

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

      // Verify Image
      final contentType = response.headers.value('content-type') ?? '';
      expect(contentType, contains('image/'));

      print('Reader Image Download SUCCESS: \${response.data!.length} bytes, Content-Type: \$contentType');
    });

    test('8. Evaluate HtmlElement dynamic attribute binding', () async {
       final html = '''<a href="/online/new-9154.html" ch="1">Link</a>''';
       final jsContent = '''
         var doc = new HtmlDocument('$html');
         var el = doc.querySelector('a');
         var ch = el.attributes['ch'];
         doc.dispose();
         ch;
       ''';
       final res = JsEngine().runCode(jsContent);
       expect(res, equals('1'), reason: 'el.attributes["ch"] must work in flutter_qjs');
       print('HtmlElement.attributes mapping is SUPPORTED.');
    });
  });
}
