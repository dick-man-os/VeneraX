import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_state_repository.dart';
import 'package:venera/foundation/res.dart';
import 'same_work_group.dart';
import 'search_relevance.dart';
import 'title_normalizer.dart';

/// Immutable operation snapshot. The installed object also distinguishes
/// artifacts/versions sharing a runtime key; the scheduler locks that key.
class SearchProvider {
  SearchProvider(ComicSource source)
    : source = source,
      options = List.unmodifiable(
        (source.searchPageData!.searchOptions ?? []).map(
          (option) => option.defaultValue,
        ),
      );

  final ComicSource source;
  final List<String> options;
  bool get isCurrent => identical(ComicSource.find(source.key), source);

  Future<Res<List<Comic>>> load(String query) {
    final data = source.searchPageData!;
    if (data.loadPage != null) {
      return data.loadPage!(query, 1, List.of(options));
    }
    if (data.loadNext != null) {
      return data.loadNext!(query, null, List.of(options));
    }
    return Future.value(const Res.error('Search is unavailable'));
  }
}

class SearchSourceResult {
  const SearchSourceResult({
    this.comics = const [],
    this.loading = true,
    this.error,
    this.pagination,
  });
  final List<Comic> comics;
  final bool loading;
  final String? error;
  final dynamic pagination;
}

class _SearchOperation {
  _SearchOperation(this.owner, this.key, this.isCurrent, this.run);
  final Object owner;
  final String key;
  final bool Function() isCurrent;
  final Future<void> Function() run;
}

/// Shared across aggregate routes, including disposed routes whose transport
/// has not settled. No timeout releases a slot while its request still runs.
class SearchOperationAdmission {
  static final shared = SearchOperationAdmission();
  final _queue = <_SearchOperation>[];
  final _activeKeys = <String>{};

  void discardQueued(Object owner) {
    _queue.removeWhere((operation) => identical(operation.owner, owner));
  }

  void submit({
    required Object owner,
    required String key,
    required bool Function() isCurrent,
    required Future<void> Function() run,
  }) {
    _queue.add(_SearchOperation(owner, key, isCurrent, run));
    _drain();
  }

  void _drain() {
    _queue.removeWhere((operation) => !operation.isCurrent());
    while (_activeKeys.length < 4) {
      final index = _queue.indexWhere(
        (operation) => !_activeKeys.contains(operation.key),
      );
      if (index < 0) break;
      final operation = _queue.removeAt(index);
      _activeKeys.add(operation.key);
      unawaited(_execute(operation));
    }
  }

  Future<void> _execute(_SearchOperation operation) async {
    try {
      await operation.run();
    } finally {
      _activeKeys.remove(operation.key);
      _drain();
    }
  }
}

class AggregatedSearchController extends ChangeNotifier {
  AggregatedSearchController({
    SearchOperationAdmission? admission,
    ComicStateRepository? repository,
  }) : _admission = admission ?? SearchOperationAdmission.shared,
       _repository = repository ?? const ComicStateRepository();

  final SearchOperationAdmission _admission;
  final ComicStateRepository _repository;
  int _generation = 0;
  bool _disposed = false;
  String query = '';
  List<SearchProvider> providers = const [];
  List<SearchSourceResult> _results = const [];
  final _candidates = <int, List<SearchCandidate>>{};
  List<BestMatchGroup> _ranked = const [];
  List<BestMatchGroup>? _frozen;
  static const bestMatchesLimit = 20;

  int get generation => _generation;
  List<SearchSourceResult> get results => List.unmodifiable(_results);
  List<BestMatchGroup> get bestMatches => _frozen ?? _ranked;
  int get pendingSources => _results.where((result) => result.loading).length;
  bool get hasUpdatedMatches =>
      _frozen != null && !listEquals(_signature(_frozen!), _signature(_ranked));

  List<Object> _signature(List<BestMatchGroup> groups) => [
    for (final group in groups)
      (
        group.key,
        group.best.identity,
        Object.hashAll(
          group.alternatives.map((candidate) => candidate.identity),
        ),
      ),
  ];

  // Freeze actual cards, titles and alternatives so pointer/focus targets
  // cannot move. Explicit refresh applies the latest deterministic order.
  void freezePlacement() {
    _frozen ??= _ranked;
  }

  void refreshPlacement() {
    _frozen = null;
    notifyListeners();
  }

  void search(String rawQuery, List<SearchProvider> snapshot) {
    if (_disposed) return;
    final generation = ++_generation;
    _admission.discardQueued(this);
    query = rawQuery;
    providers = List.unmodifiable(snapshot);
    _results = List.generate(
      providers.length,
      (_) => SearchSourceResult(loading: rawQuery.trim().isNotEmpty),
    );
    _candidates.clear();
    _ranked = const [];
    _frozen = null;
    notifyListeners();
    if (rawQuery.trim().isEmpty) return;
    final matcher = SearchRelevanceMatcher(rawQuery);
    for (var index = 0; index < providers.length; index++) {
      final provider = providers[index];
      bool current() =>
          !_disposed && generation == _generation && provider.isCurrent;
      _admission.submit(
        owner: this,
        key: provider.source.key,
        isCurrent: current,
        run: () async {
          try {
            final response = await provider.load(rawQuery);
            if (!current()) return;
            if (response.error) {
              _results[index] = SearchSourceResult(
                loading: false,
                error: response.errorMessage,
              );
            } else {
              final comics = List<Comic>.unmodifiable(response.data);
              final candidates = <SearchCandidate>[];
              Map<(String, String), AcceptedSearchWork> acceptedWorks =
                  const {};
              try {
                acceptedWorks = _repository.peekAcceptedSearchWorks(comics);
              } catch (_) {
                // Relationship data is optional ranking evidence. A damaged
                // cache must not turn a successful provider into a failure.
              }
              for (var item = 0; item < comics.length; item++) {
                final comic = comics[item];
                final acceptedWork = acceptedWorks[(comic.sourceKey, comic.id)];
                final title = SearchTitle(comic.title);
                candidates.add(
                  SearchCandidate(
                    comic: comic,
                    sourceOrder: index,
                    itemOrder: item,
                    title: title,
                    sourceName: provider.source.name,
                    artifact: provider.source,
                    acceptedWorkId: acceptedWork?.workId,
                    relevance: matcher.match(
                      title,
                      acceptedAliases: acceptedWork?.aliases ?? const [],
                    ),
                  ),
                );
              }
              _results[index] = SearchSourceResult(
                comics: comics,
                loading: false,
                pagination: response.subData,
              );
              _candidates[index] = candidates;
              _ranked = List.unmodifiable(
                rankBestMatches(
                  _candidates.values.expand((value) => value),
                ).take(bestMatchesLimit),
              );
            }
          } catch (error) {
            if (!current()) return;
            _results[index] = SearchSourceResult(
              loading: false,
              error: error.toString(),
            );
          }
          if (current()) notifyListeners();
        },
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _admission.discardQueued(this);
    super.dispose();
  }
}
