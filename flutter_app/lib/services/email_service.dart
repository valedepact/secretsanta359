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
  /// Failures are swallowed - a notification email must never block joining.
  static Future<void> notifyOrganizerOfJoin(String groupId, String participantName) async {
    try {
      await SupabaseService.client.functions.invoke(
        'notify-organizer-join',
        body: {'group_id': groupId, 'participant_name': participantName},
      );
    } catch (_) {
      // Intentionally ignored.
    }
  }
}
