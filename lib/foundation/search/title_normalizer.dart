import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Query-local keys only. These must never replace persisted work identities.
class SearchTitle {
  SearchTitle(String raw)
    : identity = identityKey(raw),
      relevance = relevanceKey(raw),
      components = List.unmodifiable(
        _canonical(unorm.nfkc(raw))
            .split(_punctuation)
            .map(relevanceKey)
            .where((part) => part.isNotEmpty),
      );

  final String identity;
  final String relevance;
  final List<String> components;
  late final List<int> runes = relevance.runes.toList(growable: false);
  late final Set<String> tokens = relevance.split(' ').toSet();

  static final _whitespace = RegExp(
    r'[\s\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+',
  );
  static final _punctuation = RegExp(
    r'''[\[\](){}:;,\-!?./\\"'、。・「」『』【】〈〉《》]+''',
  );

  static String _canonical(String value) {
    final widthFolded = String.fromCharCodes(
      value.runes.map((rune) {
        if (rune >= 0xff01 && rune <= 0xff5e) return rune - 0xfee0;
        return rune == 0x3000 ? 0x20 : rune;
      }),
    );
    return widthFolded
        .toLowerCase()
        .replaceAll(RegExp('[：﹕∶]'), ':')
        .replaceAll(RegExp('[‐‑‒–—―﹘﹣]'), '-')
        .replaceAll(RegExp('[‘’]'), "'")
        .replaceAll(RegExp('[“”]'), '"')
        .replaceAll(RegExp('[﹙]'), '(')
        .replaceAll(RegExp('[﹚]'), ')')
        .replaceAll(RegExp('[﹝]'), '[')
        .replaceAll(RegExp('[﹞]'), ']')
        .replaceAll(_whitespace, ' ')
        .trim();
  }

  // NFC preserves compatibility distinctions such as circled edition digits.
  static String identityKey(String raw) => _canonical(unorm.nfc(raw));
  static String relevanceKey(String raw) => _canonical(
    unorm.nfkc(raw),
  ).replaceAll(_punctuation, ' ').replaceAll(_whitespace, ' ').trim();

  static bool isCjk(int rune) =>
      (rune >= 0x3400 && rune <= 0x9fff) ||
      (rune >= 0x20000 && rune <= 0x323af) ||
      (rune >= 0x3040 && rune <= 0x30ff) ||
      (rune >= 0xac00 && rune <= 0xd7af) ||
      (rune >= 0x1100 && rune <= 0x11ff);
}
