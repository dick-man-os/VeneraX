import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/search/aggregated_search_controller.dart';
import 'package:venera/utils/translations.dart';

class BestMatchesSection extends StatelessWidget {
  const BestMatchesSection({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final AggregatedSearchController controller;
  final ValueChanged<Comic> onOpen;

  @override
  Widget build(BuildContext context) {
    final groups = controller.bestMatches;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text('Best Matches'.tl),
          subtitle: Text(
            controller.pendingSources > 0
                ? 'Searching @n sources'.tlParams({
                    'n': controller.pendingSources,
                  })
                : 'From loaded source results'.tl,
          ),
          trailing: IconButton(
            tooltip: 'Show updated matches'.tl,
            onPressed: controller.hasUpdatedMatches
                ? controller.refreshPlacement
                : null,
            icon: const Icon(Icons.refresh),
          ),
        ),
        // Reserve the same area while loading, so source shelves do not jump.
        SizedBox(
          height: 260,
          child: groups.isEmpty
              ? Center(
                  child: Text(
                    controller.pendingSources > 0
                        ? 'Searching'.tl
                        : 'No search results found'.tl,
                  ),
                )
              : Focus(
                  onFocusChange: (focused) {
                    if (focused) controller.freezePlacement();
                  },
                  child: MouseRegion(
                    onEnter: (_) => controller.freezePlacement(),
                    child: Listener(
                      onPointerDown: (_) => controller.freezePlacement(),
                      child: ListView.separated(
                        key: PageStorageKey((
                          'best-matches',
                          controller.generation,
                        )),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: groups.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          final comic = group.best.comic;
                          return SizedBox(
                            key: ValueKey(group.key),
                            width: 176,
                            child: Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  children: [
                                    SimpleComicTile(
                                      comic: comic,
                                      width: 98,
                                      height: 136,
                                      showFavorite: true,
                                      onTap: () => onOpen(comic),
                                    ),
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      height: 40,
                                      child: Text(
                                        comic.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      height: 48,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: group.alternatives.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(width: 6),
                                        itemBuilder: (_, alternativeIndex) {
                                          final candidate = group
                                              .alternatives[alternativeIndex];
                                          return ActionChip(
                                            avatar: const Icon(
                                              Icons.open_in_new,
                                              size: 16,
                                            ),
                                            tooltip:
                                                '${candidate.sourceName}: ${candidate.comic.title}',
                                            label: Text(candidate.sourceName),
                                            onPressed: () =>
                                                onOpen(candidate.comic),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
