import 'dart:js_interop';

@JS('yesxtreamExitApp')
external void _yesxtreamExitApp();

/// Exits the web app on Samsung Tizen / LG webOS Smart TVs.
void exitSmartTvApp() {
  try {
    _yesxtreamExitApp();
  } catch (_) {}
}

