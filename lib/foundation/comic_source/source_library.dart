import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:venera/foundation/appdata.dart';

/// A remote catalog of comic sources (an `index.json` URL). The app can hold
/// many of these at once; they drive discovery and update resolution. The
/// installed copy of a source is still single-per-key on disk — libraries only
/// describe where a source can be found and which one wins when several offer
/// the same key.
class ComicSourceLibrary {
  ComicSourceLibrary({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.priority = 0,
    this.lastChecked,
  });

  /// Stable identifier derived from the normalized URL, so the same library on
  /// two devices converges to the same id after sync instead of diverging into
  /// duplicates.
  final String id;

  String name;
  String url;
  bool enabled;

  /// Ascending = checked first; the lowest value wins a same-key conflict.
  int priority;

  /// Epoch ms of the last successful catalog fetch (null = never). Device-local
  /// timing only; informational after sync.
  int? lastChecked;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'enabled': enabled,
    'priority': priority,
    'lastChecked': lastChecked,
  };

  factory ComicSourceLibrary.fromJson(Map<String, dynamic> json) {
    return ComicSourceLibrary(
      id:
          json['id']?.toString() ??
          stableLibraryId(json['url']?.toString() ?? ''),
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      enabled: json['enabled'] != false,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      lastChecked: (json['lastChecked'] as num?)?.toInt(),
    );
  }
}

/// Where an installed source came from and which libraries currently offer it.
class SourceProvenance {
  SourceProvenance({
    List<String>? libraryIds,
    this.originId,
    this.updateLibraryId,
    this.artifactFileName,
  }) : libraryIds = libraryIds ?? [];

  /// Every enabled library whose catalog currently lists this key. Rebuilt on
  /// each full update check.
  List<String> libraryIds;

  /// The library this copy was installed from. Written once at install and kept
  /// sticky across catalog churn and update-reloads. Drives the origin badge
  /// and the removal-cascade fallback.
  String? originId;

  /// The library selected for updates. Retained for inferred legacy sources
  /// without an origin so artifact ownership survives restart.
  String? updateLibraryId;

  /// Exact `fileName` of the catalog artifact occupying this runtime-key slot.
  /// Null only for sideloaded sources and records created before artifact-aware
  /// provenance was introduced.
  String? artifactFileName;

  Map<String, dynamic> toJson() => {
    'libraryIds': libraryIds,
    'originId': originId,
    'updateLibraryId': updateLibraryId,
    'artifactFileName': artifactFileName,
  };

  factory SourceProvenance.fromJson(Map<String, dynamic> json) {
    return SourceProvenance(
      libraryIds:
          (json['libraryIds'] as List?)?.map((e) => e.toString()).toList() ??
          [],
      originId: json['originId']?.toString(),
      updateLibraryId: json['updateLibraryId']?.toString(),
      artifactFileName: json['artifactFileName']?.toString(),
    );
  }
}

/// One concrete artifact offered by a source library.
///
/// A runtime key can have several artifacts, so callers must keep these as a
/// list until [resolveCatalogArtifact] has selected the installed identity.
class CatalogSourceArtifact {
  const CatalogSourceArtifact({
    required this.libraryId,
    required this.runtimeKey,
    required this.fileName,
    required this.version,
    required this.downloadUrl,
  });

  final String libraryId;
  final String runtimeKey;
  final String fileName;
  final String version;

  /// Resolved URL, or an empty string for a malformed catalog entry. Malformed
  /// siblings remain candidates so they cannot create false uniqueness.
  final String downloadUrl;
}

enum CatalogArtifactResolutionStatus {
  selected,
  missing,
  ambiguous,
  unreachable,
}

/// Explicit artifact-resolution result. Unresolved states are intentionally
/// distinct so ambiguity cannot be mistaken for an ordinary "no update".
class CatalogArtifactResolution {
  const CatalogArtifactResolution._(this.status, [this.artifact]);

  const CatalogArtifactResolution.selected(CatalogSourceArtifact artifact)
    : this._(CatalogArtifactResolutionStatus.selected, artifact);

  const CatalogArtifactResolution.missing()
    : this._(CatalogArtifactResolutionStatus.missing);

  const CatalogArtifactResolution.ambiguous()
    : this._(CatalogArtifactResolutionStatus.ambiguous);

  const CatalogArtifactResolution.unreachable()
    : this._(CatalogArtifactResolutionStatus.unreachable);

  final CatalogArtifactResolutionStatus status;
  final CatalogSourceArtifact? artifact;

  bool get isSelected => status == CatalogArtifactResolutionStatus.selected;
}

/// Resolves the exact artifact occupying [runtimeKey] in [libraryId].
///
/// [installedFileName] is a legacy-only hint. Fresh catalog installations must
/// persist [artifactFileName] directly instead of deriving it from a disk path.
CatalogArtifactResolution resolveCatalogArtifact({
  required String libraryId,
  required String runtimeKey,
  required Iterable<CatalogSourceArtifact> artifacts,
  required bool libraryReachable,
  String? artifactFileName,
  String? installedFileName,
}) {
  if (!libraryReachable) {
    return const CatalogArtifactResolution.unreachable();
  }
  final candidates = artifacts
      .where(
        (artifact) =>
            artifact.libraryId == libraryId &&
            artifact.runtimeKey == runtimeKey,
      )
      .toList();

  if (artifactFileName != null) {
    final exact = candidates
        .where((artifact) => artifact.fileName == artifactFileName)
        .toList();
    if (exact.length == 1) {
      return exact.single.downloadUrl.isEmpty
          ? const CatalogArtifactResolution.missing()
          : CatalogArtifactResolution.selected(exact.single);
    }
    return exact.isEmpty
        ? const CatalogArtifactResolution.missing()
        : const CatalogArtifactResolution.ambiguous();
  }

  if (installedFileName != null) {
    final basenameMatches = candidates
        .where((artifact) => artifact.fileName == installedFileName)
        .toList();
    if (basenameMatches.length == 1) {
      return basenameMatches.single.downloadUrl.isEmpty
          ? const CatalogArtifactResolution.missing()
          : CatalogArtifactResolution.selected(basenameMatches.single);
    }
    if (basenameMatches.length > 1) {
      return const CatalogArtifactResolution.ambiguous();
    }
  }

  if (candidates.length == 1) {
    return candidates.single.downloadUrl.isEmpty
        ? const CatalogArtifactResolution.missing()
        : CatalogArtifactResolution.selected(candidates.single);
  }
  return candidates.isEmpty
      ? const CatalogArtifactResolution.missing()
      : const CatalogArtifactResolution.ambiguous();
}

/// Resolves an explicitly chosen alternate library without silently picking
/// one of its duplicate same-key variants. A library carrying the current
/// artifact keeps exact identity; otherwise only its sole same-key artifact is
/// a safe library-level choice.
CatalogArtifactResolution resolveAlternateLibraryArtifact({
  required String libraryId,
  required String runtimeKey,
  required Iterable<CatalogSourceArtifact> artifacts,
  required bool libraryReachable,
  String? currentArtifactFileName,
  String? installedFileName,
}) {
  final candidates = artifacts
      .where(
        (artifact) =>
            artifact.libraryId == libraryId &&
            artifact.runtimeKey == runtimeKey,
      )
      .toList();
  final carriesCurrentArtifact =
      currentArtifactFileName != null &&
      candidates.any(
        (artifact) => artifact.fileName == currentArtifactFileName,
      );
  return resolveCatalogArtifact(
    libraryId: libraryId,
    runtimeKey: runtimeKey,
    artifacts: candidates,
    libraryReachable: libraryReachable,
    artifactFileName: carriesCurrentArtifact ? currentArtifactFileName : null,
    installedFileName: currentArtifactFileName == null
        ? installedFileName
        : null,
  );
}

/// Builds the sticky provenance written after a verified catalog install.
SourceProvenance provenanceForCatalogInstall({
  required String libraryId,
  required String artifactFileName,
  SourceProvenance? previous,
}) {
  final provenance = previous ?? SourceProvenance();
  provenance.originId = libraryId;
  provenance.updateLibraryId = libraryId;
  provenance.artifactFileName = artifactFileName;
  if (!provenance.libraryIds.contains(libraryId)) {
    provenance.libraryIds.add(libraryId);
  }
  return provenance;
}

/// Ensures a downloaded catalog entry actually installs the runtime slot it
/// advertised before any provenance is recorded.
void validateCatalogInstallRuntimeKey({
  required String catalogRuntimeKey,
  required String parsedRuntimeKey,
}) {
  if (catalogRuntimeKey != parsedRuntimeKey) {
    throw StateError(
      "Catalog key '$catalogRuntimeKey' does not match parsed source key '$parsedRuntimeKey'",
    );
  }
}

/// Validates a resolved target against the installed runtime/provenance.
/// Returns null when execution may proceed, otherwise an actionable reason.
String? validateCatalogUpdateTarget({
  required String installedRuntimeKey,
  required SourceProvenance provenance,
  required CatalogSourceArtifact? target,
}) {
  if (target == null) {
    return 'No validated catalog artifact target';
  }
  if (target.runtimeKey != installedRuntimeKey) {
    return 'Catalog target runtime key does not match installed source';
  }
  final governingLibraryId = provenance.originId ?? provenance.updateLibraryId;
  if (governingLibraryId == null || target.libraryId != governingLibraryId) {
    return 'Catalog target library does not match source provenance';
  }
  if (provenance.artifactFileName == null ||
      target.fileName != provenance.artifactFileName) {
    return 'Catalog target artifact does not match source provenance';
  }
  return null;
}

enum CatalogArtifactInstallState { available, installed, occupied }

/// Artifact-aware catalog-row state. An occupied sibling stays non-actionable
/// instead of offering an Add button that can only fail duplicate-key checks.
CatalogArtifactInstallState catalogArtifactInstallState({
  required CatalogSourceArtifact candidate,
  required Iterable<CatalogSourceArtifact> libraryArtifacts,
  required bool runtimeKeyInstalled,
  required SourceProvenance? provenance,
  String? installedFileName,
}) {
  if (!runtimeKeyInstalled) return CatalogArtifactInstallState.available;

  final artifactFileName = provenance?.artifactFileName;
  if (artifactFileName != null) {
    final governingLibraryId =
        provenance?.originId ?? provenance?.updateLibraryId;
    if (governingLibraryId != candidate.libraryId) {
      return CatalogArtifactInstallState.occupied;
    }
    final resolution = resolveCatalogArtifact(
      libraryId: candidate.libraryId,
      runtimeKey: candidate.runtimeKey,
      artifacts: libraryArtifacts,
      libraryReachable: true,
      artifactFileName: artifactFileName,
    );
    return resolution.artifact != null &&
            resolution.artifact!.fileName == candidate.fileName
        ? CatalogArtifactInstallState.installed
        : CatalogArtifactInstallState.occupied;
  }

  final resolution = resolveCatalogArtifact(
    libraryId: candidate.libraryId,
    runtimeKey: candidate.runtimeKey,
    artifacts: libraryArtifacts,
    libraryReachable: true,
    installedFileName: installedFileName,
  );
  final selected = resolution.artifact;
  return selected != null &&
          selected.libraryId == candidate.libraryId &&
          selected.fileName == candidate.fileName
      ? CatalogArtifactInstallState.installed
      : CatalogArtifactInstallState.occupied;
}

/// Normalizes the URL parts that are case-insensitive while preserving the
/// path and query, whose casing may identify different server resources.
String canonicalLibraryUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return 'empty';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
    var fallback = trimmed;
    while (fallback.endsWith('/')) {
      fallback = fallback.substring(0, fallback.length - 1);
    }
    return fallback.isEmpty ? 'empty' : fallback;
  }
  final pathSegments = uri.pathSegments.toList();
  while (pathSegments.isNotEmpty && pathSegments.last.isEmpty) {
    pathSegments.removeLast();
  }
  return uri
      .replace(
        scheme: uri.scheme.toLowerCase(),
        host: uri.host.toLowerCase(),
        pathSegments: pathSegments,
      )
      .toString();
}

/// Derives a stable, cross-device id from a canonical catalog URL.
String stableLibraryId(String url) {
  return md5
      .convert(utf8.encode(canonicalLibraryUrl(url)))
      .toString()
      .substring(0, 12);
}

@visibleForTesting
String allocateLibraryId(String url, Iterable<String> usedIds) {
  final used = usedIds.toSet();
  final canonicalBytes = utf8.encode(canonicalLibraryUrl(url));
  final md5Digest = md5.convert(canonicalBytes).toString();
  final candidates = [
    md5Digest.substring(0, 12),
    md5Digest,
    sha256.convert(canonicalBytes).toString(),
  ];
  for (final candidate in candidates) {
    if (!used.contains(candidate)) {
      return candidate;
    }
  }
  throw StateError('Unable to allocate a unique library id');
}

@visibleForTesting
ComicSourceLibrary? findLibraryByUrl(
  Iterable<ComicSourceLibrary> libraries,
  String url,
) {
  final canonical = canonicalLibraryUrl(url);
  for (final library in libraries) {
    if (canonicalLibraryUrl(library.url) == canonical) {
      return library;
    }
  }
  return null;
}

/// Derives a short, readable default library name from a catalog URL so the
/// list never shows an overlong raw URL. Prefers the host; appends a
/// distinguishing path segment when several catalogs share one host.
String defaultLibraryName(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) {
    return url.trim();
  }
  final segments = uri.pathSegments
      .where((s) => s.isNotEmpty && !s.toLowerCase().endsWith('.json'))
      .toList();
  if (segments.isEmpty) {
    return uri.host;
  }
  return "${uri.host}/${segments.last}";
}

/// Reads and mutates the ordered library registry stored in
/// `appdata.settings['comicSourceLibraries']`, plus the per-source provenance
/// map in `appdata.settings['comicSourceProvenance']`. Pure data logic; the UI
/// and the update checker call into this.
class ComicSourceLibraryManager {
  static const _librariesKey = 'comicSourceLibraries';
  static const _provenanceKey = 'comicSourceProvenance';
  static const _migratedKey = 'comicSourceLibrariesMigrated';

  /// All libraries, sorted by priority ascending (winner first).
  static List<ComicSourceLibrary> all() {
    final raw = appdata.settings[_librariesKey];
    if (raw is! List) {
      return [];
    }
    final list = raw
        .whereType<Map>()
        .map((e) => ComicSourceLibrary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    list.sort((a, b) => a.priority.compareTo(b.priority));
    return list;
  }

  static List<ComicSourceLibrary> enabled() =>
      all().where((e) => e.enabled).toList();

  static ComicSourceLibrary? find(String id) {
    for (final lib in all()) {
      if (lib.id == id) return lib;
    }
    return null;
  }

  static ComicSourceLibrary? _findIn(
    List<ComicSourceLibrary> libraries,
    String id,
  ) {
    for (final lib in libraries) {
      if (lib.id == id) return lib;
    }
    return null;
  }

  /// Persists [libraries], re-densifies priority to list order, mirrors the
  /// primary URL into the legacy setting, then saves (which triggers sync).
  static void save(List<ComicSourceLibrary> libraries) {
    for (var i = 0; i < libraries.length; i++) {
      libraries[i].priority = i;
    }
    appdata.settings[_librariesKey] = libraries.map((e) => e.toJson()).toList();
    appdata.settings['comicSourceListUrl'] = _primaryUrlOf(libraries);
    appdata.saveData();
  }

  static String _primaryUrlOf(List<ComicSourceLibrary> libraries) {
    final sorted = List<ComicSourceLibrary>.from(libraries)
      ..sort((a, b) => a.priority.compareTo(b.priority));
    for (final lib in sorted) {
      if (lib.enabled && lib.url.isNotEmpty) return lib.url;
    }
    return '';
  }

  /// Adds a library for [url] if the current URL is not already present.
  /// Returns the (possibly pre-existing) library.
  static ComicSourceLibrary add(String name, String url) {
    final libraries = all();
    // Stored ids intentionally survive URL edits because provenance references
    // them. Deduplicate by the current URL, then allocate around any stale id.
    final existing = findLibraryByUrl(libraries, url);
    if (existing != null) {
      if (name.isNotEmpty) existing.name = name;
      save(libraries);
      return existing;
    }
    final id = allocateLibraryId(url, libraries.map((library) => library.id));
    final lib = ComicSourceLibrary(
      id: id,
      name: name.isNotEmpty ? name : defaultLibraryName(url),
      url: url,
      priority: libraries.length,
    );
    libraries.add(lib);
    save(libraries);
    return lib;
  }

  /// Updates a library's display name and/or catalog URL in place. The library
  /// id is intentionally kept stable (provenance records reference it), even if
  /// the URL — from which a fresh id would derive — changes.
  static void edit(String id, {String? name, String? url}) {
    final libraries = all();
    final lib = _findIn(libraries, id);
    if (lib == null) return;
    if (name != null && name.isNotEmpty) {
      lib.name = name;
    } else if (name != null && url != null) {
      // Name cleared: fall back to a readable default from the (new) URL.
      lib.name = defaultLibraryName(url);
    }
    if (url != null && url.isNotEmpty) {
      lib.url = url;
    }
    save(libraries);
  }

  static void setEnabled(String id, bool enabled) {
    final libraries = all();
    final lib = _findIn(libraries, id);
    if (lib == null) return;
    lib.enabled = enabled;
    save(libraries);
  }

  /// Reorders the library at [oldIndex] to [newIndex] in the priority-sorted
  /// list, then re-densifies priority. [newIndex] is a final list index
  /// (already adjusted for the removal, as `onReorderItem` reports).
  static void reorder(int oldIndex, int newIndex) {
    final libraries = all();
    if (oldIndex < 0 || oldIndex >= libraries.length) return;
    final moved = libraries.removeAt(oldIndex);
    libraries.insert(newIndex.clamp(0, libraries.length), moved);
    save(libraries);
  }

  /// Removes the library and detaches it from every provenance record. Never
  /// uninstalls a source — the installed copy is independent of discovery.
  static void remove(String id) {
    final libraries = all()..removeWhere((e) => e.id == id);
    final map = _provenanceMap();
    for (final entry in map.entries) {
      final prov = SourceProvenance.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
      final removedOwnedArtifact =
          prov.artifactFileName != null &&
          (prov.originId == id || prov.updateLibraryId == id);
      prov.libraryIds.remove(id);
      if (prov.originId == id) {
        prov.originId = null;
      }
      if (prov.updateLibraryId == id) {
        prov.updateLibraryId = removedOwnedArtifact
            ? null
            : prov.libraryIds.isNotEmpty
            ? prov.libraryIds.first
            : null;
      } else if (removedOwnedArtifact) {
        // The artifact was bound to the removed origin. Do not silently attach
        // it to another same-key library merely because that library offers it.
        prov.updateLibraryId = null;
      }
      map[entry.key] = prov.toJson();
    }
    appdata.settings[_provenanceKey] = map;
    save(libraries);
  }

  static Map<String, dynamic> _provenanceMap() {
    final raw = appdata.settings[_provenanceKey];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {};
  }

  static SourceProvenance? provenanceFor(String key) {
    final raw = _provenanceMap()[key];
    if (raw is Map) {
      return SourceProvenance.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  static void setProvenance(String key, SourceProvenance provenance) {
    final map = _provenanceMap();
    map[key] = provenance.toJson();
    appdata.settings[_provenanceKey] = map;
    appdata.saveData();
  }

  /// Batch-writes provenance for many keys in a single persist. Used by the
  /// update checker so a full check does not schedule one sync upload per
  /// source. Saved without triggering an upload — discovery state is derived
  /// and will be rebuilt on the next check anyway.
  static void setProvenanceBatch(Map<String, SourceProvenance> entries) {
    if (entries.isEmpty) return;
    final map = _provenanceMap();
    entries.forEach((key, prov) => map[key] = prov.toJson());
    appdata.settings[_provenanceKey] = map;
    appdata.saveData(false);
  }

  /// Records a successful catalog fetch time for [id] without triggering a sync
  /// upload (purely device-local timing).
  static void markChecked(String id) {
    final libraries = all();
    final lib = _findIn(libraries, id);
    if (lib == null) return;
    lib.lastChecked = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < libraries.length; i++) {
      libraries[i].priority = i;
    }
    appdata.settings[_librariesKey] = libraries.map((e) => e.toJson()).toList();
    appdata.saveData(false);
  }

  /// Records the origin library for a freshly installed [key]. Keeps any
  /// previously discovered library ids.
  static void recordOrigin(
    String key,
    String libraryId, {
    String? artifactFileName,
  }) {
    var prov = provenanceFor(key) ?? SourceProvenance();
    if (artifactFileName != null) {
      prov = provenanceForCatalogInstall(
        libraryId: libraryId,
        artifactFileName: artifactFileName,
        previous: prov,
      );
    } else {
      prov.originId = libraryId;
      prov.updateLibraryId = libraryId;
      if (!prov.libraryIds.contains(libraryId)) {
        prov.libraryIds.add(libraryId);
      }
    }
    setProvenance(key, prov);
  }

  /// Removes a source's provenance entirely. Call only on genuine uninstall,
  /// never on an update-reload (which keeps the same key).
  static void clearProvenance(String key) {
    final map = _provenanceMap();
    if (map.remove(key) != null) {
      appdata.settings[_provenanceKey] = map;
      appdata.saveData();
    }
  }

  /// Folds a legacy single `comicSourceListUrl` into the library list when it
  /// is set but not yet represented as a library. Runs on every init (not
  /// one-shot): this self-heals the case where a legacy URL arrives AFTER first
  /// launch via WebDAV sync or a backup import from an old-version device, which
  /// a one-shot flag would miss — leaving the URL field populated but zero
  /// libraries and discovery silently dead.
  ///
  /// It cannot resurrect a deliberately-deleted library: deleting libraries
  /// rewrites the mirror via [save] → `_primaryUrlOf`, so a removed library's
  /// URL no longer appears in `comicSourceListUrl` and is never re-folded. Uses
  /// `saveData(false)` to avoid scheduling an upload mid-initialization.
  static void migrateIfNeeded() {
    final legacy = (appdata.settings['comicSourceListUrl']?.toString() ?? '')
        .trim();
    final libraries = all();
    final alreadyPresent =
        legacy.isEmpty || findLibraryByUrl(libraries, legacy) != null;
    if (!alreadyPresent) {
      final id = allocateLibraryId(
        legacy,
        libraries.map((library) => library.id),
      );
      libraries.add(
        ComicSourceLibrary(
          id: id,
          name: defaultLibraryName(legacy),
          url: legacy,
          priority: libraries.length,
        ),
      );
      for (var i = 0; i < libraries.length; i++) {
        libraries[i].priority = i;
      }
      appdata.settings[_librariesKey] = libraries
          .map((e) => e.toJson())
          .toList();
      appdata.settings[_migratedKey] = true;
      appdata.saveData(false);
    } else if (appdata.settings[_migratedKey] != true) {
      // Nothing to fold, but record that migration has run at least once.
      appdata.settings[_migratedKey] = true;
      appdata.saveData(false);
    }
  }
}
