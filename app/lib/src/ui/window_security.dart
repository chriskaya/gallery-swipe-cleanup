/// Toggles FLAG_SECURE on the activity window (MainActivity.kt sets it before
/// the first frame; this only lets the user opt out, or back in).
library;

import 'package:flutter/services.dart';

abstract interface class WindowSecurity {
  Future<void> setSecure(bool secure);
}

class ChannelWindowSecurity implements WindowSecurity {
  const ChannelWindowSecurity();

  static const _channel = MethodChannel('fr.kayanet.tamis/window');

  @override
  Future<void> setSecure(bool secure) =>
      _channel.invokeMethod<void>('setSecure', {'secure': secure});
}
