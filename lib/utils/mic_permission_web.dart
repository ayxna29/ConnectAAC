import 'dart:html' as html;

Future<bool> requestBrowserMic() async {
  try {
    final md = html.window.navigator.mediaDevices;
    if (md != null) {
      await md.getUserMedia({'audio': true});
    } else {
      // Fallback to older API (may throw on some browsers)
      await html.window.navigator.getUserMedia(audio: true);
    }
    return true;
  } catch (e) {
    // The user denied permission or the browser blocked it
    // ignore: avoid_print
    print('requestBrowserMic error: $e');
    return false;
  }
}
