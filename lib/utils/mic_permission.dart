// Cross-platform wrapper for requesting microphone permission on web.
// This file uses a conditional import to pick a web-friendly implementation
// when compiled to the browser, and a no-op stub on other platforms.

import 'mic_permission_nonweb.dart'
    if (dart.library.html) 'mic_permission_web.dart'
    as impl;

/// Attempts to request microphone access on web. Returns true if the user
/// granted access (or the request succeeded). On non-web platforms this
/// returns false (the native permission flow should be used).
Future<bool> requestBrowserMic() => impl.requestBrowserMic();
