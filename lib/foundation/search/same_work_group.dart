import 'package:venera/foundation/comic_source/comic_source.dart';
import 'search_relevance.dart';
import 'title_normalizer.dart';

enum SearchGroupingConfidence { exactSafe, aliasSafe, probable, unsafe }

class SearchCandidate {
  SearchCandidate({
    required this.comic,
    required this.sourceOrder,
    required this.itemOrder,
    required this.relevance,
    required this.title,
    required this.sourceName,
    required this.artifact,
    this.pageOrder = 0,
    this.acceptedWorkId,
  });

  final Comic comic;
  final String sourceName;
  final Object artifact;
  final int sourceOrder;
  final int pageOrder;
  final int itemOrder;
  final SearchTitle title;
  final SearchRelevance relevance;
  final String? acceptedWorkId;

  // A view key, never persisted or substituted for source/id navigation.
  (String, String) get identity => (comic.sourceKey, comic.id);

  static int compareProviderOrder(SearchCandidate a, SearchCandidate b) {
    var result = a.sourceOrder.compareTo(b.sourceOrder);
    if (result == 0) result = a.pageOrder.compareTo(b.pageOrder);
    if (result == 0) result = a.itemOrder.compareTo(b.itemOrder);
    if (result == 0) result = a.comic.sourceKey.compareTo(b.comic.sourceKey);
    if (result == 0) result = a.comic.id.compareTo(b.comic.id);
    return result;
  }

  static int compare(SearchCandidate a, SearchCandidate b) {
    final relevance = a.relevance.compareTo(b.relevance);
    return relevance == 0 ? compareProviderOrder(a, b) : relevance;
  }
}

class BestMatchGroup {
  BestMatchGroup(List<SearchCandidate> members)
    : alternatives = List.unmodifiable(
        members..sort(SearchCandidate.compareProviderOrder),
      ) {
    best = alternatives.reduce(
      (a, b) => SearchCandidate.compare(a, b) <= 0 ? a : b,
    );
  }

  final List<SearchCandidate> alternatives;
  late final SearchCandidate best;
  SearchCandidate get anchor => alternatives.first;
  Object get key => anchor.acceptedWorkId ?? anchor.identity;
  SearchGroupingConfidence get confidence => alternatives.length > 1
      ? SearchGroupingConfidence.aliasSafe
      : SearchGroupingConfidence.exactSafe;
}

/// Title equality without independent identity evidence is only probable.
/// Neither title/cover similarity nor candidate confidence authorizes merging.
SearchGroupingConfidence groupingConfidence(
  SearchCandidate a,
  SearchCandidate b,
) {
  if (a.identity == b.identity) return SearchGroupingConfidence.exactSafe;
  if (a.acceptedWorkId != null && a.acceptedWorkId == b.acceptedWorkId) {
    return SearchGroupingConfidence.aliasSafe;
  }
  if (a.title.identity == b.title.identity) {
    return SearchGroupingConfidence.probable;
  }
  return SearchGroupingConfidence.unsafe;
}

List<BestMatchGroup> rankBestMatches(Iterable<SearchCandidate> candidates) {
  final ordered = candidates.toList()
    ..sort(SearchCandidate.compareProviderOrder);
  final seen = <(String, String)>{};
  final groups = <Object, List<SearchCandidate>>{};
  for (final candidate in ordered) {
    if (!seen.add(candidate.identity)) continue;
    final key = candidate.acceptedWorkId ?? candidate.identity;
    (groups[key] ??= []).add(candidate);
  }
  return groups.values.map(BestMatchGroup.new).toList()
    ..sort((a, b) => SearchCandidate.compare(a.best, b.best));
}
