import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';

Comic searchComic(
  String title, {
  String source = 'a',
  String? id,
  String cover = '',
}) => Comic(title, cover, id ?? title, null, const [], '', source, null, null);

ComicSource searchSource(
  String key,
  SearchFunction? load, {
  SearchNextFunction? next,
  LoadComicFunc? detail,
  String version = '1.0.0',
}) => ComicSource(
  key,
  key,
  null,
  null,
  null,
  null,
  const [],
  SearchPageData(null, load, next),
  null,
  detail,
  null,
  null,
  null,
  null,
  '$key.js',
  '',
  version,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  false,
  false,
  null,
  null,
);

Future<Res<List<Comic>>> emptySearch(
  String query,
  int page,
  List<String> options,
) async => const Res([]);
