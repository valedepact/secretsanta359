import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/pwa_install.dart';

/// Shows a native "Install App" action once the browser's install prompt
/// becomes available, or a manual instruction on iOS Safari (which never
/// fires beforeinstallprompt). Renders nothing on platforms where neither
/// applies (native Android/iOS builds, desktop browsers without support).
class InstallAppButton extends StatefulWidget {
  const InstallAppButton({super.key});

  @override
  State<InstallAppButton> createState() => _InstallAppButtonState();
}

class _InstallAppButtonState extends State<InstallAppButton> {
  bool _canInstall = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _canInstall = isPwaInstallAvailable();
    if (!_canInstall) {
      // beforeinstallprompt fires asynchronously after page load - poll
      // briefly rather than requiring a page refresh to notice it.
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (isPwaInstallAvailable()) {
          setState(() => _canInstall = true);
          timer.cancel();
        }
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_canInstall) {
      return OutlinedButton.icon(
        onPressed: () => promptPwaInstall(),
        icon: const Icon(Icons.install_mobile),
        label: const Text('Install App'),
      );
    }
    if (isLikelyIosSafari()) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'On iPhone/iPad: tap Share, then "Add to Home Screen" to install.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
