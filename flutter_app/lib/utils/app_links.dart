import 'package:flutter/foundation.dart';

/// Base origin used to build shareable invite/reveal links.
/// On web this is the actual deployed origin; elsewhere it falls back to a
/// placeholder so the app still compiles for mobile builds.
String get appBaseUrl => kIsWeb ? Uri.base.origin : 'https://secretsanta359.app';

String inviteLink(String shareCode) => '$appBaseUrl/join?code=$shareCode';

String revealLink(String revealCode) => '$appBaseUrl/join?reveal=$revealCode';
