// lib/services/url_opener.dart
// Opens URL using platform channel (no external browser dependency needed)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

Future<bool> openExternalUrl(String url) async {
  try {
    // Try platform channel first
    const channel = MethodChannel('com.nipino.manabu/url_opener');
    final result = await channel.invokeMethod<bool>('open', {'url': url});
    if (result == true) return true;
  } catch (_) {}

  // Fallback: show dialog with URL and copy button
  final context = _navigatorKey.currentContext;
  if (context != null && context.mounted) {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Open Link'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Copy this link and open in your browser:',
            style: TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          SelectableText(url,
            style: const TextStyle(fontSize: 12, color: Color(0xFF1565C0))),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(_);
            },
            child: const Text('Copy Link')),
          TextButton(
            onPressed: () => Navigator.pop(_),
            child: const Text('Close')),
        ],
      ),
    );
    return true;
  }
  return false;
}
