// lib/services/url_opener.dart
//
// Opens a URL in the external browser via a native platform channel instead
// of the url_launcher plugin — avoids pulling in androidx.browser (and any
// other new native dependency) just to fire an implicit ACTION_VIEW intent
// that two lines of native code already does for free.
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.nipino.manabu/url_opener');

Future<bool> openExternalUrl(String url) async {
  try {
    return await _channel.invokeMethod<bool>('open', {'url': url}) ?? false;
  } on PlatformException {
    return false;
  }
}
