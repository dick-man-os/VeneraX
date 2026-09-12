import 'dart:math' as math;
import 'title_normalizer.dart';

enum SearchRelevanceTier {
  exact,
  alias,
  strongPrefix,
  strongContainment,
  token,
  fuzzy,
  providerWeak,
}

class SearchRelevance implements Comparable<SearchRelevance> {
  const SearchRelevance(this.tier, {this.coverage = 0, this.distance = 0});

  final SearchRelevanceTier tier;
  final int coverage;
  final int distance;

  @override
  int compareTo(SearchRelevance other) {
    var result = tier.index.compareTo(other.tier.index);
    if (result == 0) result = other.coverage.compareTo(coverage);
    if (result == 0) result = distance.compareTo(other.distance);
    return result;
  }
}

/// Local, bounded title matching. Provider queries are never rewritten.
class SearchRelevanceMatcher {
  SearchRelevanceMatcher(String query) : query = SearchTitle(query);
  final SearchTitle query;

  SearchRelevance match(
    SearchTitle title, {
    Iterable<String> acceptedAliases = const [],
  }) {
    const weak = SearchRelevance(SearchRelevanceTier.providerWeak);
    if (query.identity.isEmpty) return weak;
    if (title.identity == query.identity) {
      return const SearchRelevance(SearchRelevanceTier.exact, coverage: 10000);
    }
    if (acceptedAliases.any(
      (alias) => SearchTitle.identityKey(alias) == query.identity,
    )) {
      return const SearchRelevance(SearchRelevanceTier.alias, coverage: 10000);
    }
    final q = query.runes;
    final t = title.runes;
    if (q.isEmpty || t.isEmpty) return weak;
    final hasCjk = q.any(SearchTitle.isCjk);
    final meaningful = q.length >= 2;
    final coverage = math.min(10000, q.length * 10000 ~/ t.length);
    final prefix =
        title.relevance.startsWith(query.relevance) &&
        (hasCjk ||
            title.relevance.length == query.relevance.length ||
            title.relevance[query.relevance.length] == ' ');
    if (meaningful &&
        (title.components.contains(query.relevance) ||
            (prefix && coverage >= 5000))) {
      return SearchRelevance(
        SearchRelevanceTier.strongPrefix,
        coverage: coverage,
      );
    }
    if (q.length >= (hasCjk ? 2 : 4) &&
        coverage >= 5000 &&
        _contains(title.relevance, query.relevance, wordBoundary: !hasCjk)) {
      return SearchRelevance(
        SearchRelevanceTier.strongContainment,
        coverage: coverage,
      );
    }
    var overlap = 0;
    if (hasCjk) {
      final bigrams = <String>{};
      for (var i = 0; i + 1 < q.length; i++) {
        if (SearchTitle.isCjk(q[i]) && SearchTitle.isCjk(q[i + 1])) {
          bigrams.add(String.fromCharCodes(q.sublist(i, i + 2)));
        }
      }
      overlap = bigrams.where(title.relevance.contains).length;
      if (overlap > 0) {
        return SearchRelevance(
          SearchRelevanceTier.token,
          coverage: overlap * 10000 ~/ math.max(1, q.length - 1),
        );
      }
    } else {
      final tokens = query.tokens
          .where((token) => token.runes.length >= 2)
          .toSet();
      overlap = tokens.intersection(title.tokens).length;
      if (overlap > 0) {
        return SearchRelevance(
          SearchRelevanceTier.token,
          coverage: overlap * 10000 ~/ tokens.length,
        );
      }
    }
    // Short CJK queries never receive fuzzy boosts. Rune counts also bound
    // CPU/memory and avoid treating one emoji as two UTF-16 characters.
    if (q.length >= 4 && t.length >= 4 && q.length <= 128 && t.length <= 128) {
      final maxLength = math.max(q.length, t.length);
      final limit = math.min(3, maxLength ~/ 5);
      if ((q.length - t.length).abs() <= limit) {
        final distance = _distance(q, t, limit);
        if (distance <= limit) {
          return SearchRelevance(
            SearchRelevanceTier.fuzzy,
            coverage: (maxLength - distance) * 10000 ~/ maxLength,
            distance: distance,
          );
        }
      }
    }
    return weak;
  }

  static bool _contains(
    String title,
    String query, {
    required bool wordBoundary,
  }) {
    var start = title.indexOf(query);
    while (start >= 0) {
      final end = start + query.length;
      if (!wordBoundary ||
          ((start == 0 || title[start - 1] == ' ') &&
              (end == title.length || title[end] == ' '))) {
        return true;
      }
      start = title.indexOf(query, start + 1);
    }
    return false;
  }

  static int _distance(List<int> a, List<int> b, int limit) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final row = List<int>.filled(b.length + 1, limit + 1);
      row[0] = i;
      var minimum = limit + 1;
      for (
        var j = math.max(1, i - limit);
        j <= math.min(b.length, i + limit);
        j++
      ) {
        row[j] = math.min(
          math.min(row[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        );
        minimum = math.min(minimum, row[j]);
      }
      if (minimum > limit) return limit + 1;
      previous = row;
    }
    return previous.last;
  }
}
