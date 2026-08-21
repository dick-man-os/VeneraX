import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/source_library.dart';

CatalogSourceArtifact _artifact({
  String libraryId = 'lib1',
  String runtimeKey = 'copy_manga',
  required String fileName,
  String version = '2.0.0',
  String? url,
}) {
  return CatalogSourceArtifact(
    libraryId: libraryId,
    runtimeKey: runtimeKey,
    fileName: fileName,
    version: version,
    downloadUrl: url ?? 'https://example.com/$fileName',
  );
}

void main() {
  group('stableLibraryId', () {
    test('is deterministic for the same URL', () {
      final a = stableLibraryId('https://example.com/index.json');
      final b = stableLibraryId('https://example.com/index.json');
      expect(a, b);
    });

    test('normalizes scheme, host, and trailing slashes so the same logical '
        'library converges to one id across devices', () {
      final canonical = stableLibraryId('https://example.com/repo');
      expect(stableLibraryId('HTTPS://Example.com/repo/'), canonical);
      expect(stableLibraryId('  https://EXAMPLE.com/repo  '), canonical);
      expect(stableLibraryId('https://example.com/repo///'), canonical);
    });

    test('preserves case-sensitive path and query components', () {
      expect(
        stableLibraryId('https://example.com/Repo/index.json'),
        isNot(stableLibraryId('https://example.com/repo/index.json')),
      );
      expect(
        stableLibraryId('https://example.com/index.json?branch=Main'),
        isNot(stableLibraryId('https://example.com/index.json?branch=main')),
      );
    });

    test('differs for different URLs', () {
      expect(
        stableLibraryId('https://a.com/index.json'),
        isNot(stableLibraryId('https://b.com/index.json')),
      );
    });

    test('produces a short stable-length token', () {
      expect(stableLibraryId('https://example.com/index.json').length, 12);
      expect(stableLibraryId('').length, 12);
    });
  });

  group('allocateLibraryId', () {
    test(
      'uses a deterministic full digest when a stale id occupies the hash',
      () {
        const url = 'https://example.com/index.json';
        final base = stableLibraryId(url);
        final allocated = allocateLibraryId(url, [base]);

        expect(allocated, isNot(base));
        expect(allocated.length, 32);
        expect(allocateLibraryId(url, ['other', base]), allocated);
        expect(allocateLibraryId(url, [base, 'other']), allocated);
      },
    );

    test('compares current URLs instead of an id left behind by an edit', () {
      const oldUrl = 'https://example.com/old/index.json';
      const currentUrl = 'https://example.com/current/index.json';
      final editedLibrary = ComicSourceLibrary(
        id: stableLibraryId(oldUrl),
        name: 'Edited',
        url: currentUrl,
      );

      expect(findLibraryByUrl([editedLibrary], oldUrl), isNull);
      expect(findLibraryByUrl([editedLibrary], currentUrl), editedLibrary);
      expect(
        allocateLibraryId(oldUrl, [editedLibrary.id]),
        isNot(editedLibrary.id),
      );
    });
  });

  group('defaultLibraryName', () {
    test('uses host when path is just an index file', () {
      expect(
        defaultLibraryName('https://example.com/index.json'),
        'example.com',
      );
      expect(defaultLibraryName('https://example.com'), 'example.com');
      expect(defaultLibraryName('https://example.com/'), 'example.com');
    });

    test('appends a distinguishing path segment so co-hosted repos differ', () {
      expect(
        defaultLibraryName('https://example.com/repoA/index.json'),
        'example.com/repoA',
      );
      expect(
        defaultLibraryName('https://example.com/repoB/index.json'),
        'example.com/repoB',
      );
    });

    test('falls back to the raw string when not a URL', () {
      expect(defaultLibraryName('not a url'), 'not a url');
    });
  });

  group('ComicSourceLibrary serialization', () {
    test('round-trips through JSON', () {
      final lib = ComicSourceLibrary(
        id: 'abc123',
        name: 'My Library',
        url: 'https://example.com/index.json',
        enabled: false,
        priority: 3,
        lastChecked: 1700000000000,
      );
      final restored = ComicSourceLibrary.fromJson(lib.toJson());
      expect(restored.id, lib.id);
      expect(restored.name, lib.name);
      expect(restored.url, lib.url);
      expect(restored.enabled, lib.enabled);
      expect(restored.priority, lib.priority);
      expect(restored.lastChecked, lib.lastChecked);
    });

    test('derives a stable id from url when id is missing in legacy json', () {
      final restored = ComicSourceLibrary.fromJson({
        'name': 'Legacy',
        'url': 'https://example.com/index.json',
      });
      expect(restored.id, stableLibraryId('https://example.com/index.json'));
      expect(restored.enabled, isTrue); // defaults to enabled
    });
  });

  group('SourceProvenance serialization', () {
    test('round-trips through JSON', () {
      final prov = SourceProvenance(
        libraryIds: ['lib1', 'lib2'],
        originId: 'lib1',
        updateLibraryId: 'lib2',
        artifactFileName: 'copy_manga.js',
      );
      final restored = SourceProvenance.fromJson(prov.toJson());
      expect(restored.libraryIds, ['lib1', 'lib2']);
      expect(restored.originId, 'lib1');
      expect(restored.updateLibraryId, 'lib2');
      expect(restored.artifactFileName, 'copy_manga.js');
    });

    test('old JSON defaults artifact identity to null', () {
      final prov = SourceProvenance.fromJson({});
      expect(prov.libraryIds, isEmpty);
      expect(prov.originId, isNull);
      expect(prov.updateLibraryId, isNull);
      expect(prov.artifactFileName, isNull);
    });

    test('fresh standard and multi-account installs keep exact filenames', () {
      final standard = provenanceForCatalogInstall(
        libraryId: 'lib1',
        artifactFileName: 'copy_manga.js',
      );
      final multi = provenanceForCatalogInstall(
        libraryId: 'lib1',
        artifactFileName: 'copy_manga_multi_accounts.js',
      );

      expect(standard.originId, 'lib1');
      expect(standard.updateLibraryId, 'lib1');
      expect(standard.artifactFileName, 'copy_manga.js');
      expect(multi.artifactFileName, 'copy_manga_multi_accounts.js');
    });

    test('fresh install rejects a parsed runtime key mismatch', () {
      expect(
        () => validateCatalogInstallRuntimeKey(
          catalogRuntimeKey: 'copy_manga',
          parsedRuntimeKey: 'other_source',
        ),
        throwsStateError,
      );
      expect(
        () => validateCatalogInstallRuntimeKey(
          catalogRuntimeKey: 'copy_manga',
          parsedRuntimeKey: 'copy_manga',
        ),
        returnsNormally,
      );
    });
  });

  group('catalog artifact resolution', () {
    final standard = _artifact(fileName: 'copy_manga.js');
    final multi = _artifact(fileName: 'copy_manga_multi_accounts.js');

    test('known standard artifact resolves only the standard URL', () {
      final result = resolveCatalogArtifact(
        libraryId: 'lib1',
        runtimeKey: 'copy_manga',
        artifacts: [standard, multi],
        libraryReachable: true,
        artifactFileName: 'copy_manga.js',
      );

      expect(result.status, CatalogArtifactResolutionStatus.selected);
      expect(result.artifact, same(standard));
    });

    test('known multi-account artifact resolves only the multi URL', () {
      final result = resolveCatalogArtifact(
        libraryId: 'lib1',
        runtimeKey: 'copy_manga',
        artifacts: [standard, multi],
        libraryReachable: true,
        artifactFileName: 'copy_manga_multi_accounts.js',
      );

      expect(result.status, CatalogArtifactResolutionStatus.selected);
      expect(result.artifact, same(multi));
    });

    test('duplicate catalog order does not affect exact selection', () {
      CatalogArtifactResolution resolve(List<CatalogSourceArtifact> artifacts) {
        return resolveCatalogArtifact(
          libraryId: 'lib1',
          runtimeKey: 'copy_manga',
          artifacts: artifacts,
          libraryReachable: true,
          artifactFileName: 'copy_manga.js',
        );
      }

      expect(
        resolve([standard, multi]).artifact?.downloadUrl,
        standard.downloadUrl,
      );
      expect(
        resolve([multi, standard]).artifact?.downloadUrl,
        standard.downloadUrl,
      );
    });

    test('legacy exact basename uniquely identifies one artifact', () {
      final result = resolveCatalogArtifact(
        libraryId: 'lib1',
        runtimeKey: 'copy_manga',
        artifacts: [standard, multi],
        libraryReachable: true,
        installedFileName: 'copy_manga_multi_accounts.js',
      );

      expect(result.artifact, same(multi));
    });

    test('legacy unique-key candidate infers successfully', () {
      final unique = _artifact(runtimeKey: 'unique', fileName: 'unique.js');
      final result = resolveCatalogArtifact(
        libraryId: 'lib1',
        runtimeKey: 'unique',
        artifacts: [unique],
        libraryReachable: true,
        installedFileName: 'renamed-local-file.js',
      );

      expect(result.artifact, same(unique));
    });

    test('ambiguous legacy shared key produces no target', () {
      final result = resolveCatalogArtifact(
        libraryId: 'lib1',
        runtimeKey: 'copy_manga',
        artifacts: [standard, multi],
        libraryReachable: true,
        installedFileName: 'copy_manga(0).js',
      );

      expect(result.status, CatalogArtifactResolutionStatus.ambiguous);
      expect(result.artifact, isNull);
    });

    test(
      'malformed sibling still prevents legacy first-artifact selection',
      () {
        final malformedSibling = CatalogSourceArtifact(
          libraryId: 'lib1',
          runtimeKey: 'copy_manga',
          fileName: 'copy_manga_multi_accounts.js',
          version: '2.0.0',
          downloadUrl: '',
        );
        final result = resolveCatalogArtifact(
          libraryId: 'lib1',
          runtimeKey: 'copy_manga',
          artifacts: [standard, malformedSibling],
          libraryReachable: true,
          installedFileName: 'copy_manga(0).js',
        );

        expect(result.status, CatalogArtifactResolutionStatus.ambiguous);
        expect(result.artifact, isNull);
      },
    );

    test('known artifact disappearance never falls back to its sibling', () {
      final result = resolveCatalogArtifact(
        libraryId: 'lib1',
        runtimeKey: 'copy_manga',
        artifacts: [multi],
        libraryReachable: true,
        artifactFileName: 'copy_manga.js',
      );

      expect(result.status, CatalogArtifactResolutionStatus.missing);
      expect(result.artifact, isNull);
    });

    test('known renamed artifact fails closed even when it is unique', () {
      final renamed = _artifact(fileName: 'copy_manga_renamed.js');
      final result = resolveCatalogArtifact(
        libraryId: 'lib1',
        runtimeKey: 'copy_manga',
        artifacts: [renamed],
        libraryReachable: true,
        artifactFileName: 'copy_manga.js',
      );

      expect(result.status, CatalogArtifactResolutionStatus.missing);
    });

    test('cross-library candidates cannot override the governing library', () {
      final owner = _artifact(libraryId: 'owner', fileName: 'copy_manga.js');
      final foreign = _artifact(
        libraryId: 'foreign',
        fileName: 'copy_manga.js',
        url: 'https://foreign.example/copy_manga.js',
      );
      final result = resolveCatalogArtifact(
        libraryId: 'owner',
        runtimeKey: 'copy_manga',
        artifacts: [foreign, owner],
        libraryReachable: true,
        artifactFileName: 'copy_manga.js',
      );

      expect(result.artifact, same(owner));
    });

    test('unreachable library is explicit and produces no target', () {
      final result = resolveCatalogArtifact(
        libraryId: 'lib1',
        runtimeKey: 'copy_manga',
        artifacts: [standard],
        libraryReachable: false,
        artifactFileName: 'copy_manga.js',
      );

      expect(result.status, CatalogArtifactResolutionStatus.unreachable);
      expect(result.artifact, isNull);
    });

    test('ordinary unique-key source retains existing behavior', () {
      final unique = _artifact(runtimeKey: 'unique', fileName: 'unique.js');
      final result = resolveCatalogArtifact(
        libraryId: 'lib1',
        runtimeKey: 'unique',
        artifacts: [unique],
        libraryReachable: true,
      );

      expect(result.artifact, same(unique));
    });

    test(
      'alternate library never first-matches duplicate same-key artifacts',
      () {
        CatalogArtifactResolution resolve(
          List<CatalogSourceArtifact> artifacts,
        ) {
          return resolveAlternateLibraryArtifact(
            libraryId: 'lib1',
            runtimeKey: 'copy_manga',
            artifacts: artifacts,
            libraryReachable: true,
            currentArtifactFileName: 'not-offered-here.js',
            installedFileName: 'not-offered-here.js',
          );
        }

        expect(
          resolve([standard, multi]).status,
          CatalogArtifactResolutionStatus.ambiguous,
        );
        expect(
          resolve([multi, standard]).status,
          CatalogArtifactResolutionStatus.ambiguous,
        );
      },
    );

    test('alternate library may retain one exact known artifact', () {
      final result = resolveAlternateLibraryArtifact(
        libraryId: 'lib1',
        runtimeKey: 'copy_manga',
        artifacts: [multi, standard],
        libraryReachable: true,
        currentArtifactFileName: 'copy_manga.js',
      );

      expect(result.artifact, same(standard));
    });
  });

  group('catalog execution and installed-state gates', () {
    test('target must match runtime key, library, and artifact provenance', () {
      final provenance = SourceProvenance(
        originId: 'lib1',
        updateLibraryId: 'lib1',
        artifactFileName: 'copy_manga.js',
      );
      final valid = _artifact(fileName: 'copy_manga.js');
      final wrongArtifact = _artifact(fileName: 'copy_manga_multi_accounts.js');
      final wrongKey = _artifact(
        runtimeKey: 'other',
        fileName: 'copy_manga.js',
      );

      expect(
        validateCatalogUpdateTarget(
          installedRuntimeKey: 'copy_manga',
          provenance: provenance,
          target: valid,
        ),
        isNull,
      );
      expect(
        validateCatalogUpdateTarget(
          installedRuntimeKey: 'copy_manga',
          provenance: provenance,
          target: wrongArtifact,
        ),
        isNotNull,
      );
      expect(
        validateCatalogUpdateTarget(
          installedRuntimeKey: 'copy_manga',
          provenance: provenance,
          target: wrongKey,
        ),
        isNotNull,
      );
      expect(
        validateCatalogUpdateTarget(
          installedRuntimeKey: 'copy_manga',
          provenance: provenance,
          target: null,
        ),
        isNotNull,
      );
    });

    test('only exact known artifact row is installed; sibling is occupied', () {
      final standard = _artifact(fileName: 'copy_manga.js');
      final multi = _artifact(fileName: 'copy_manga_multi_accounts.js');
      final provenance = SourceProvenance(
        originId: 'lib1',
        artifactFileName: 'copy_manga.js',
      );

      expect(
        catalogArtifactInstallState(
          candidate: standard,
          libraryArtifacts: [standard, multi],
          runtimeKeyInstalled: true,
          provenance: provenance,
        ),
        CatalogArtifactInstallState.installed,
      );
      expect(
        catalogArtifactInstallState(
          candidate: multi,
          libraryArtifacts: [standard, multi],
          runtimeKeyInstalled: true,
          provenance: provenance,
        ),
        CatalogArtifactInstallState.occupied,
      );
    });

    test('legacy ambiguous rows are occupied rather than addable', () {
      final standard = _artifact(fileName: 'copy_manga.js');
      final multi = _artifact(fileName: 'copy_manga_multi_accounts.js');

      expect(
        catalogArtifactInstallState(
          candidate: standard,
          libraryArtifacts: [standard, multi],
          runtimeKeyInstalled: true,
          provenance: SourceProvenance(),
          installedFileName: 'copy_manga(0).js',
        ),
        CatalogArtifactInstallState.occupied,
      );
    });
  });
}
