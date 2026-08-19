import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/pages/explore_page.dart';

void main() {
  test('Explore tab display label uses actual source.name and not literal interpolation token', () {
    final sourceA = ComicSource(
      'Source A', 'source_a', null, null, null, null,
      [ExplorePageData('Popular', ExplorePageType.singlePageWithMultiPart, null, null, null, null)],
      null, null, null, null, null, null, null, '', '', '', null, null, null, null, null, null, null, null, const {}, null, null, null, false, false, null, null
    );

    final sourceB = ComicSource(
      'Source B', 'source_b', null, null, null, null,
      [ExplorePageData('Popular', ExplorePageType.singlePageWithMultiPart, null, null, null, null)],
      null, null, null, null, null, null, null, '', '', '', null, null, null, null, null, null, null, null, const {}, null, null, null, false, false, null, null
    );

    ComicSourceManager().all().clear(); // wait, all() returns a list, can't clear _sources this way if it's a copy
    // Actually, I don't need to clear, just add.
    ComicSourceManager().add(sourceA);
    ComicSourceManager().add(sourceB);

    final pages = ['source_a::Popular', 'source_b::Popular'];

    final labelA = getExploreTabLabel('source_a::Popular', pages);
    final labelB = getExploreTabLabel('source_b::Popular', pages);

    expect(labelA, 'Source A · Popular');
    expect(labelB, 'Source B · Popular');

    // Ensure it's not the literal literal
    expect(labelA, isNot(contains('\${comicSource.name}')));
  });
}
