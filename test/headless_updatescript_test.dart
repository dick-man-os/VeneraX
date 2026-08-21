import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_source/source_library.dart';
import 'package:venera/headless.dart';

void main() {
  final manager = ComicSourceManager();

  tearDown(() {
    manager.replaceCatalogUpdateState(
      availableUpdates: const {},
      targets: const {},
      issues: const {},
    );
  });

  test(
    'ambiguous shared-key source is not updated and is actionable',
    () async {
      manager.replaceCatalogUpdateState(
        availableUpdates: const {},
        targets: const {},
        issues: const {'copy_manga': CatalogArtifactResolution.ambiguous()},
      );
      final output = <Map<String, dynamic>>[];
      var updateCalled = false;

      await runHeadlessComicSourceUpdates(
        checkForUpdates: () async => 0,
        updateSource: (source) async {
          updateCalled = true;
        },
        output: output.add,
      );

      expect(updateCalled, isFalse);
      expect(output.last['status'], 'error');
      expect(output.last['message'], contains('need action'));
      final skipped = output.last['data']['skipped'] as List;
      expect(skipped, hasLength(1));
      expect(skipped.single['sourceKey'], 'copy_manga');
      expect(skipped.single['status'], 'ambiguous');
    },
  );
}
