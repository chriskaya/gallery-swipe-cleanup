/// Hands the current item to the Android share sheet.
///
/// The MediaStore content:// URI itself is shared with a one-off read grant
/// (MainActivity), so nothing is copied to the app cache and the receiving
/// app only ever gets that one item.
library;

import 'package:flutter/services.dart';

abstract interface class Sharer {
  Future<void> share({required String uri, required String? mimeType});
}

class ChannelSharer implements Sharer {
  const ChannelSharer();

  static const _channel = MethodChannel('fr.kayanet.tamis/share');

  @override
  Future<void> share({required String uri, required String? mimeType}) =>
      _channel.invokeMethod<void>('share', {'uri': uri, 'mimeType': mimeType});
}
