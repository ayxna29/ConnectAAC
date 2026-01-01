Future<bool> requestBrowserMic() async {
  // Not running on web — caller should use native permission_handler instead.
  return false;
}
