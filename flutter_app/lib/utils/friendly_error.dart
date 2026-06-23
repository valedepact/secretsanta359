import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns a caught error into plain language for display in the UI.
/// Never shows raw exception class names, Postgres error codes, or stack
/// details to the user.
String friendlyError(Object error) {
  if (error is AuthException) {
    return error.message;
  }

  if (error is PostgrestException) {
    switch (error.code) {
      case '42501':
        return "You don't have permission to do that.";
      case '23505':
        return 'That already exists.';
      case 'P0001':
        // Raised by our own database functions/triggers with an
        // already human-readable message (e.g. "This group is not
        // accepting new participants.").
        return error.message;
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  // Manually thrown Exception('...') in our own code already has a
  // friendly message - just strip Dart's default "Exception: " prefix.
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring('Exception: '.length) : text;
}
