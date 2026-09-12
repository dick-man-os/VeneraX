import "package:flutter/material.dart";
import 'package:flutter/rendering.dart';
import 'package:venera/components/best_matches_section.dart';
import 'package:venera/foundation/search/aggregated_search_controller.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import "package:venera/components/components.dart";
import "package:venera/foundation/app.dart";
import "package:venera/foundation/appdata.dart";
import "package:venera/foundation/comic_source/comic_source.dart";
import "package:venera/foundation/favorites.dart";
import "package:venera/pages/search_result_page.dart";
import "package:venera/utils/translations.dart";

class AggregatedSearchPage extends StatefulWidget {
  const AggregatedSearchPage({super.key, required this.keyword});

  final String keyword;

  @override
  State<AggregatedSearchPage> createState() => _AggregatedSearchPageState();
}

class _AggregatedSearchPageState extends State<AggregatedSearchPage> {
  List<ComicSource> sources = [];
  late final SearchBarController controller;
  final search = AggregatedSearchController();
  var _keyword = '';

  List<ComicSource> _sourceSnapshot() {
    final seen = <String>{};
    return [
      for (final key in appdata.settings['searchSources'] as List)
        if (key is String && seen.add(key))
          if (ComicSource.find(key) case final source?)
            if (source.searchPageData != null) source,
    ];
  }

  void _search(String text) {
    _keyword = text;
    if (text.trim().isNotEmpty) appdata.addSearchHistory(text);
    sources = _sourceSnapshot();
    search.search(text, sources.map(SearchProvider.new).toList());
  }

  void _sourcesChanged() {
    final next = _sourceSnapshot();
    if (next.length == sources.length &&
        Iterable<int>.generate(
          next.length,
        ).every((i) => identical(next[i], sources[i]))) {
      return;
    }
    sources = next;
    search.search(_keyword, sources.map(SearchProvider.new).toList());
  }

  void _favoriteChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    controller = SearchBarController(
      currentText: widget.keyword,
      onSearch: _search,
    );
    _search(widget.keyword);
    ComicSourceManager().addListener(_sourcesChanged);
    LocalFavoritesManager().addListener(_favoriteChanged);
  }

  @override
  void dispose() {
    ComicSourceManager().removeListener(_sourcesChanged);
    LocalFavoritesManager().removeListener(_favoriteChanged);
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: search,
      builder: (context, _) {
        final results = search.results;
        return NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle) {
              search.freezePlacement();
            }
            return false;
          },
          child: SmoothCustomScrollView(
            scrollbarTopPadding: context.padding.top + 56,
            slivers: [
              SliverSearchBar(controller: controller),
              if (_keyword.trim().isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: BestMatchesSection(
                    key: ValueKey(search.generation),
                    controller: search,
                    onOpen: (comic) {
                      search.freezePlacement();
                      context.to(
                        () => ComicPage(
                          id: comic.id,
                          sourceKey: comic.sourceKey,
                          title: comic.title,
                          cover: comic.cover,
                        ),
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: ListTile(title: Text('Results by Source'.tl)),
                ),
                SliverList(
                  key: ValueKey(search.generation),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return _SliverSearchResult(
                      key: ValueKey(sources[index].key),
                      source: sources[index],
                      keyword: _keyword,
                      result: results[index],
                    );
                  }, childCount: sources.length),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SliverSearchResult extends StatefulWidget {
  const _SliverSearchResult({
    required this.source,
    required this.keyword,
    required this.result,
    super.key,
  });

  final ComicSource source;

  final SearchSourceResult result;

  final String keyword;

  @override
  State<_SliverSearchResult> createState() => _SliverSearchResultState();
}

class _SliverSearchResultState extends State<_SliverSearchResult>
    with AutomaticKeepAliveClientMixin {
  bool get isLoading => widget.result.loading;

  static const _kComicHeight = 162.0;

  get _comicWidth => _kComicHeight * 0.7;

  static const _kLeftPadding = 16.0;

  List<Comic> get comics => widget.result.comics;

  String? get error =>
      widget.result.error?.startsWith('CloudflareException') == true
      ? 'Cloudflare verification required'.tl
      : widget.result.error;

  Widget buildPlaceHolder() {
    return Container(
      height: _kComicHeight,
      width: _comicWidth,
      margin: const EdgeInsets.only(left: _kLeftPadding),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget buildComic(Comic c) {
    return SimpleComicTile(
      comic: c,
      withTitle: true,
      showFavorite: true,
    ).paddingLeft(_kLeftPadding).paddingBottom(2);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return InkWell(
      onTap: () {
        context.to(
          () => SearchResultPage(
            text: widget.keyword,
            sourceKey: widget.source.key,
          ),
        );
      },
      child: Column(
        children: [
          ListTile(
            mouseCursor: SystemMouseCursors.click,
            title: Text(widget.source.name),
          ),
          if (isLoading)
            SizedBox(
              height: _kComicHeight,
              width: double.infinity,
              child: Shimmer(
                child: LayoutBuilder(
                  builder: (context, constrains) {
                    var itemWidth = _comicWidth + _kLeftPadding;
                    var items = (constrains.maxWidth / itemWidth).ceil();
                    return Stack(
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: Row(
                            children: List.generate(
                              items,
                              (index) => buildPlaceHolder(),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            )
          else if (error != null || comics.isEmpty)
            SizedBox(
              height: _kComicHeight,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error ?? "No search results found".tl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                ],
              ).paddingHorizontal(16),
            )
          else
            SizedBox(
              height: _kComicHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [for (var c in comics) buildComic(c)],
              ),
            ),
        ],
      ).paddingBottom(16),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
