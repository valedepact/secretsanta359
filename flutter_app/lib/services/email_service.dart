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
}
