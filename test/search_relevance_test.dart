import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/search/title_normalizer.dart';
import 'package:venera/foundation/search/search_relevance.dart';

void main() {
  test(
    'identity normalizes Unicode, width, punctuation, case and whitespace',
    () {
      expect(
        SearchTitle.identityKey('  ＴＯＷＥＲ：［GＯＤ］—  Café\u00a0 '),
        'tower:[god]- café',
      );
      expect(
        SearchTitle.identityKey('Cafe\u0301'),
        SearchTitle.identityKey('Café'),
      );
      expect(SearchTitle.identityKey('가'), SearchTitle.identityKey('가'));
      expect(SearchTitle.identityKey('神之塔'), '神之塔');
      expect(SearchTitle.identityKey('龍'), isNot(SearchTitle.identityKey('龙')));
      expect(SearchTitle.identityKey('タワー'), 'タワー');
      expect(
        SearchTitle.identityKey('Tower [2]'),
        isNot(SearchTitle.identityKey('Tower 2')),
      );
      expect(
        SearchTitle.identityKey('Tower ①'),
        isNot(SearchTitle.identityKey('Tower 1')),
      );
      expect(
        SearchTitle.relevanceKey('Tower ①'),
        SearchTitle.relevanceKey('Tower 1'),
      );
      expect(
        SearchTitle.identityKey('ﾀﾜｰ'),
        isNot(SearchTitle.identityKey('タワー')),
      );
      expect(SearchTitle.relevanceKey('ﾀﾜｰ'), SearchTitle.relevanceKey('タワー'));
    },
  );

  test(
    'exact, prefix, containment, CJK token and weak tiers keep their order',
    () {
      final matcher = SearchRelevanceMatcher('神之塔');
      final cases = {
        '神之塔': SearchRelevanceTier.exact,
        '神之塔：番外': SearchRelevanceTier.strongPrefix,
        '死神之塔': SearchRelevanceTier.strongContainment,
        '神之犬': SearchRelevanceTier.token,
        '神之山傳說': SearchRelevanceTier.token,
        '死神故事': SearchRelevanceTier.providerWeak,
      };
      for (final entry in cases.entries) {
        expect(
          matcher.match(SearchTitle(entry.key)).tier,
          entry.value,
          reason: entry.key,
        );
      }
      expect(
        matcher
            .match(SearchTitle('神之塔'))
            .compareTo(matcher.match(SearchTitle('神之犬'))),
        lessThan(0),
      );
    },
  );

  test(
    'aliases require supplied accepted evidence; no model-known translation',
    () {
      final matcher = SearchRelevanceMatcher('神之塔');
      final title = SearchTitle('Tower of God');
      expect(matcher.match(title).tier, SearchRelevanceTier.providerWeak);
      expect(
        matcher.match(title, acceptedAliases: ['神之塔']).tier,
        SearchRelevanceTier.alias,
      );
      expect(
        SearchRelevanceMatcher(' Tower   of GOD ').match(title).tier,
        SearchRelevanceTier.exact,
      );
    },
  );

  test(
    'Latin boundary and component matching avoid short accidental prefixes',
    () {
      expect(
        SearchRelevanceMatcher('tower').match(SearchTitle('towering')).tier,
        SearchRelevanceTier.providerWeak,
      );
      expect(
        SearchRelevanceMatcher('tower').match(SearchTitle('tower god')).tier,
        SearchRelevanceTier.strongPrefix,
      );
      expect(
        SearchRelevanceMatcher('tower').match(SearchTitle('a tower')).tier,
        SearchRelevanceTier.strongContainment,
      );
      expect(
        SearchRelevanceMatcher(
          'tower',
        ).match(SearchTitle('stories: tower')).tier,
        SearchRelevanceTier.strongPrefix,
      );
      expect(
        SearchRelevanceMatcher('a').match(SearchTitle('a tale')).tier,
        SearchRelevanceTier.providerWeak,
      );
    },
  );

  test('fuzzy work is bounded and short CJK is never fuzzy', () {
    expect(
      SearchRelevanceMatcher('abcdef').match(SearchTitle('abcxef')).tier,
      SearchRelevanceTier.fuzzy,
    );
    expect(
      SearchRelevanceMatcher('abcd').match(SearchTitle('wxyz')).tier,
      SearchRelevanceTier.providerWeak,
    );
    expect(
      SearchRelevanceMatcher('神之塔').match(SearchTitle('神天塔')).tier,
      SearchRelevanceTier.providerWeak,
    );
    expect(
      SearchRelevanceMatcher('神').match(SearchTitle('神之塔')).tier,
      SearchRelevanceTier.providerWeak,
    );
    expect(
      SearchRelevanceMatcher('😀abcd').match(SearchTitle('😀abce')).tier,
      SearchRelevanceTier.fuzzy,
    );
    expect(
      SearchRelevanceMatcher(
        'a' * 129,
      ).match(SearchTitle('${'a' * 128}b')).tier,
      SearchRelevanceTier.providerWeak,
    );
    expect(
      SearchRelevanceMatcher(' ').match(SearchTitle('any')).tier,
      SearchRelevanceTier.providerWeak,
    );
    expect(
      SearchRelevanceMatcher(':').match(SearchTitle('any')).tier,
      SearchRelevanceTier.providerWeak,
    );
  });
}
