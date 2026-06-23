import 'dart:js_interop';
import 'package:web/web.dart' as web;

@JS('canInstallPwa')
external bool _canInstallPwa();

@JS('promptPwaInstall')
external JSPromise<JSBoolean> _promptPwaInstall();

bool isPwaInstallAvailable() {
  try {
    return _canInstallPwa();
  } catch (_) {
    return false;
  }
}

bool isLikelyIosSafari() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  final isIos = ua.contains('iphone') || ua.contains('ipad');
  final isOtherIosBrowser = ua.contains('crios') || ua.contains('fxios');
  return isIos && !isOtherIosBrowser;
}

Future<bool> promptPwaInstall() async {
  try {
    final accepted = await _promptPwaInstall().toDart;
    return accepted.toDart;
  } catch (_) {
    return false;
  }
}
