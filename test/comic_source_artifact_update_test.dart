import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_source/source_library.dart';
import 'package:venera/foundation/comic_source_update_tasks.dart';

void main() {
  final manager = ComicSourceManager();
  const target = CatalogSourceArtifact(
    libraryId: 'lib1',
    runtimeKey: 'copy_manga',
    fileName: 'copy_manga.js',
    version: '2.0.0',
    downloadUrl: 'https://example.com/copy_manga.js',
  );

  tearDown(() {
    manager.replaceCatalogUpdateState(
      availableUpdates: const {},
      targets: const {},
      issues: const {},
    );
  });

  test('later ambiguous resolution fully removes a stale cached target', () {
    manager.replaceCatalogUpdateState(
      availableUpdates: const {'copy_manga': '2.0.0'},
      targets: const {'copy_manga': target},
      issues: const {},
    );
    expect(manager.updateTargetFor('copy_manga'), same(target));

    manager.replaceCatalogUpdateState(
      availableUpdates: const {},
      targets: const {},
      issues: const {'copy_manga': CatalogArtifactResolution.ambiguous()},
    );

    expect(manager.updateTargetFor('copy_manga'), isNull);
    expect(manager.availableUpdates, isEmpty);
    expect(
      manager.updateIssueFor('copy_manga')?.status,
      CatalogArtifactResolutionStatus.ambiguous,
    );
  });

  test('executor gate refuses missing or mismatched catalog artifact', () {
    final provenance = SourceProvenance(
      originId: 'lib1',
      updateLibraryId: 'lib1',
      artifactFileName: 'copy_manga.js',
    );
    const sibling = CatalogSourceArtifact(
      libraryId: 'lib1',
      runtimeKey: 'copy_manga',
      fileName: 'copy_manga_multi_accounts.js',
      version: '2.0.0',
      downloadUrl: 'https://example.com/copy_manga_multi_accounts.js',
    );

    expect(
      () => ComicSourceUpdateTaskManager.validateCatalogTargetForExecution(
        installedRuntimeKey: 'copy_manga',
        provenance: provenance,
        target: null,
      ),
      throwsStateError,
    );
    expect(
      () => ComicSourceUpdateTaskManager.validateCatalogTargetForExecution(
        installedRuntimeKey: 'copy_manga',
        provenance: provenance,
        target: sibling,
      ),
      throwsStateError,
    );
    expect(
      () => ComicSourceUpdateTaskManager.validateCatalogTargetForExecution(
        installedRuntimeKey: 'copy_manga',
        provenance: provenance,
        target: target,
      ),
      returnsNormally,
    );
  });

  test('executor rejects a downloaded script with a different runtime key', () {
    expect(
      () => ComicSourceUpdateTaskManager.validateDownloadedRuntimeKey(
        installedRuntimeKey: 'copy_manga',
        downloadedRuntimeKey: 'other_source',
      ),
      throwsStateError,
    );
    expect(
      () => ComicSourceUpdateTaskManager.validateDownloadedRuntimeKey(
        installedRuntimeKey: 'copy_manga',
        downloadedRuntimeKey: 'copy_manga',
      ),
      returnsNormally,
    );
  });
}
