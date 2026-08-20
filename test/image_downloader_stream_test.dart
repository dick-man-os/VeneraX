import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/cache_manager.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/sqlite_connection.dart';
import 'package:venera/network/images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late HttpServer server;
  late StreamSubscription<HttpRequest> serverSubscription;
  late int configCalls;
  late int requestCount;
  late List<int> responseBytes;
  Future<void> Function(HttpRequest request)? requestHandler;
  final responseGates = <Completer<void>>[];
  const sourceKey = 'stream_diagnostic_source';

  String cacheKeyFor(String imageKey) => '$imageKey@$sourceKey@cid@eid';

  Future<void> respond(HttpRequest request, List<int> bytes) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  }

  Future<void> waitForRequestCount(int expected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (requestCount < expected && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (requestCount < expected) {
      throw TimeoutException(
        'Expected $expected HTTP request(s), observed $requestCount',
      );
    }
  }

  Future<File> waitForCache(String imageKey) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final file = await CacheManager().findCache(cacheKeyFor(imageKey));
      if (file != null) {
        return file;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('Cache was not populated for $imageKey');
  }

  ComicSource buildSource() {
    return ComicSource(
      'Stream diagnostic',
      sourceKey,
      null,
      null,
      null,
      null,
      const [],
      null,
      null,
      null,
      null,
      null,
      (image, cid, eid) async {
        configCalls++;
        return <String, dynamic>{
          'url': 'http://${server.address.address}:${server.port}/$image',
        };
      },
      null,
      'stream_diagnostic.js',
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

  setUp(() async {
    root = await Directory.systemTemp.createTemp('venera_image_stream_test');
    App.dataPath = root.path;
    App.cachePath = root.path;
    CacheManager.instance = null;
    // CacheManager starts an asynchronous directory scan from its constructor.
    // Let that empty initial scan finish before the test can tear the root down.
    CacheManager();
    await DatabaseGateway.instance.guardedRead(() async {});
    await pumpEventQueue();
    configCalls = 0;
    requestCount = 0;
    responseBytes = <int>[11, 22, 33, 44];
    requestHandler = null;
    responseGates.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serverSubscription = server.listen((request) async {
      requestCount++;
      final handler = requestHandler;
      if (handler != null) {
        await handler(request);
      } else {
        await respond(request, responseBytes);
      }
    });
    ComicSourceManager().add(buildSource());
  });

  tearDown(() async {
    for (final gate in responseGates) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
    ImageDownloader.cancelAllLoadingImages();
    ComicSourceManager().remove(sourceKey);
    await server.close(force: true);
    await serverSubscription.cancel();
    await CacheManager().clear();
    DatabaseGateway.instance.closeManaged('${App.dataPath}/cache.db');
    CacheManager.instance = null;
    await root.delete(recursive: true);
  });

  test(
    'immediate warm-cache subscriber does not configure or request',
    () async {
      const imageKey = 'immediate-image';
      await CacheManager().writeCache(cacheKeyFor(imageKey), [1, 2, 3]);

      final progress =
          await ImageDownloader.loadComicImage(
                imageKey,
                sourceKey,
                'cid',
                'eid',
              )
              .firstWhere((event) => event.imageBytes != null)
              .timeout(const Duration(seconds: 1));
      await pumpEventQueue();

      expect(progress.imageBytes, [1, 2, 3]);
      expect(configCalls, 0);
      expect(requestCount, 0);
    },
  );

  test(
    'listenerless warm preload neither requests nor overwrites cache',
    () async {
      const imageKey = 'warm-preload-image';
      const cachedBytes = <int>[9, 8, 7];
      await CacheManager().writeCache(cacheKeyFor(imageKey), cachedBytes);

      // Mirrors _preDownloadImage: the shared stream starts and is discarded.
      ImageDownloader.loadComicImage(imageKey, sourceKey, 'cid', 'eid');
      await pumpEventQueue();

      final progress =
          await ImageDownloader.loadComicImage(
                imageKey,
                sourceKey,
                'cid',
                'eid',
              )
              .firstWhere((event) => event.imageBytes != null)
              .timeout(const Duration(seconds: 1));
      await pumpEventQueue();
      final cached = await CacheManager().findCache(cacheKeyFor(imageKey));

      expect(progress.imageBytes, cachedBytes);
      expect(await cached!.readAsBytes(), cachedBytes);
      expect(configCalls, 0);
      expect(requestCount, 0);
    },
  );

  test(
    'listenerless cold preload eagerly requests once and populates cache',
    () async {
      const imageKey = 'cold-preload-image';

      // Mirrors _preDownloadImage on a cold disk cache.
      ImageDownloader.loadComicImage(imageKey, sourceKey, 'cid', 'eid');

      final cached = await waitForCache(imageKey);
      await pumpEventQueue();

      expect(await cached.readAsBytes(), responseBytes);
      expect(configCalls, 1);
      expect(requestCount, 1);
    },
  );

  test('concurrent cold subscribers share one underlying request', () async {
    const imageKey = 'concurrent-cold-image';
    final releaseResponse = Completer<void>();
    responseGates.add(releaseResponse);
    requestHandler = (request) async {
      await releaseResponse.future;
      await respond(request, responseBytes);
    };

    final first = ImageDownloader.loadComicImage(
      imageKey,
      sourceKey,
      'cid',
      'eid',
    ).firstWhere((event) => event.imageBytes != null);
    final second = ImageDownloader.loadComicImage(
      imageKey,
      sourceKey,
      'cid',
      'eid',
    ).firstWhere((event) => event.imageBytes != null);

    await waitForRequestCount(1);
    expect(configCalls, 1);
    expect(requestCount, 1);
    releaseResponse.complete();

    final results = await Future.wait([
      first,
      second,
    ]).timeout(const Duration(seconds: 5));
    expect(
      results.map((event) => event.imageBytes),
      everyElement(responseBytes),
    );
    expect(requestCount, 1);
  });

  test('cold cache transient failure still reaches the retry path', () async {
    const imageKey = 'retry-cold-image';
    requestHandler = (request) async {
      if (requestCount == 1) {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } else {
        await respond(request, responseBytes);
      }
    };

    final result =
        await ImageDownloader.loadComicImage(imageKey, sourceKey, 'cid', 'eid')
            .firstWhere((event) => event.imageBytes != null)
            .timeout(const Duration(seconds: 5));

    expect(result.imageBytes, responseBytes);
    expect(configCalls, 1);
    expect(requestCount, 2);
  });

  test('late cold subscriber joins the in-flight shared request', () async {
    const imageKey = 'late-cold-image';
    final requestObserved = Completer<void>();
    final releaseResponse = Completer<void>();
    responseGates.add(releaseResponse);
    requestHandler = (request) async {
      requestObserved.complete();
      await releaseResponse.future;
      await respond(request, responseBytes);
    };

    final firstResult = ImageDownloader.loadComicImage(
      imageKey,
      sourceKey,
      'cid',
      'eid',
    ).firstWhere((event) => event.imageBytes != null);

    await requestObserved.future.timeout(const Duration(seconds: 5));
    final lateResult = ImageDownloader.loadComicImage(
      imageKey,
      sourceKey,
      'cid',
      'eid',
    ).firstWhere((event) => event.imageBytes != null);
    expect(configCalls, 1);
    expect(requestCount, 1);

    releaseResponse.complete();
    final results = await Future.wait([
      firstResult,
      lateResult,
    ]).timeout(const Duration(seconds: 5));

    expect(
      results.map((event) => event.imageBytes),
      everyElement(responseBytes),
    );
    expect(requestCount, 1);
  });
}
