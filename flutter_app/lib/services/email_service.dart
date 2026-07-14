import 'supabase_service.dart';

class EmailService {
  /// Fire-and-forget call to the send-reveal-emails edge function.
  /// Failures are swallowed deliberately - email delivery must never block
  /// or fail the draw itself.
  static Future<void> sendRevealEmails(String groupId) async {
    try {
      await SupabaseService.client.functions
          .invoke('send-reveal-emails', body: {'group_id': groupId});
    } catch (_) {
      // Intentionally ignored - email delivery must never block the draw.
    }
  }

  /// Fire-and-forget call to notify the organizer that someone joined.
  /// The participant's name is looked up server-side from their own row (via
  /// their session) rather than sent from here, so there's nothing to trust.
  /// Failures are swallowed - a notification email must never block joining.
  static Future<void> notifyOrganizerOfJoin(String groupId) async {
    try {
      await SupabaseService.client.functions.invoke(
        'notify-organizer-join',
        body: {'group_id': groupId},
      );
    } catch (_) {
      // Intentionally ignored.
    }
  }
}
