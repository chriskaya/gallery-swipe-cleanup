import 'package:flutter_test/flutter_test.dart';
import 'package:tamis/src/media/media_item.dart';

void main() {
  test('default filter covers every album', () {
    const f = MediaFilter();
    expect(f.allAlbums, isTrue);
    expect(f.isDefault, isTrue);
    expect(f.includesAlbum('anything'), isTrue);
  });

  test('withAlbum works in both modes', () {
    final except = const MediaFilter.except({}).withAlbum('a', included: false);
    expect(except.excludeAlbums, isTrue);
    expect(except.includesAlbum('a'), isFalse);
    expect(except.includesAlbum('b'), isTrue);
    expect(except.withAlbum('a', included: true).allAlbums, isTrue);

    final only = const MediaFilter.only({}).withAlbum('a', included: true);
    expect(only.includesAlbum('a'), isTrue);
    expect(only.includesAlbum('b'), isFalse);
    expect(only.withAlbum('a', included: false).noAlbums, isTrue);
  });

  test('JSON round trip keeps the mode', () {
    const f = MediaFilter.only({'x'}, type: MediaTypeFilter.videos);
    expect(MediaFilter.fromJson(f.toJson()), f);
    const g = MediaFilter.except({'y'});
    expect(MediaFilter.fromJson(g.toJson()), g);
  });

  test('v0.1 JSON (allow-list only, empty = all) still reads right', () {
    expect(
      MediaFilter.fromJson({'type': 'all', 'albums': <String>[]}).allAlbums,
      isTrue,
    );
    final legacy = MediaFilter.fromJson({
      'type': 'images',
      'albums': ['a'],
    });
    expect(legacy.excludeAlbums, isFalse);
    expect(legacy.includesAlbum('a'), isTrue);
    expect(legacy.includesAlbum('b'), isFalse);
  });

  test('MediaItem JSON keeps album, mime type and size', () {
    const item = MediaItem(
      id: '1',
      kind: MediaKind.image,
      width: 1,
      height: 1,
      album: 'Camera',
      mimeType: 'image/jpeg',
      sizeBytes: 1234,
    );
    final back = MediaItem.tryFromJson(item.toJson())!;
    expect(back.album, 'Camera');
    expect(back.mimeType, 'image/jpeg');
    expect(back.sizeBytes, 1234);
  });
}
