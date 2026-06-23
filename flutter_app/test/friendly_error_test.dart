import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:secret_santa_organizer/utils/friendly_error.dart';

void main() {
  test('AuthException shows its own message', () {
    expect(friendlyError(AuthException('Invalid login credentials')),
        'Invalid login credentials');
  });

  test('PostgrestException RLS denial (42501) is translated', () {
    expect(
      friendlyError(PostgrestException(message: 'raw', code: '42501')),
      "You don't have permission to do that.",
    );
  });

  test('PostgrestException P0001 (our own raised message) passes through', () {
    expect(
      friendlyError(PostgrestException(
        message: 'This group is not accepting new participants.',
        code: 'P0001',
      )),
      'This group is not accepting new participants.',
    );
  });

  test('Unknown Postgrest error codes get a generic message', () {
    expect(
      friendlyError(PostgrestException(message: 'raw', code: '99999')),
      'Something went wrong. Please try again.',
    );
  });

  test('Plain Exception strips the Dart "Exception: " prefix', () {
    expect(friendlyError(Exception('Group not found.')), 'Group not found.');
  });
}
