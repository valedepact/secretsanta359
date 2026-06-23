import '../models/participant.dart';
import '../models/public_group_info.dart';
import '../utils/draw_algorithm.dart';
import 'supabase_service.dart';

class JoinResult {
  final String id;
  final String revealCode;

  JoinResult({required this.id, required this.revealCode});
}

class ParticipantService {
  static final _client = SupabaseService.client;

  /// Organizer-only: full participant list for a group they own (RLS-protected).
  static Future<List<Participant>> forGroup(String groupId) async {
    final rows = await _client
        .from('participants')
        .select()
        .eq('group_id', groupId)
        .order('created_at');
    return rows.map((row) => Participant.fromJson(row)).toList();
  }

  /// Anonymous join via the secured RPC - never touches the raw table directly.
  static Future<JoinResult> join({
    required String groupId,
    required String name,
    required Gender gender,
    String? email,
    String? wishlist,
  }) async {
    final rows = await _client.rpc(
      'join_group',
      params: {
        'p_group_id': groupId,
        'p_name': name,
        'p_gender': genderToString(gender),
        'p_email': email,
        'p_wishlist': wishlist,
      },
    );
    final row = (rows as List).first as Map<String, dynamic>;
    return JoinResult(id: row['id'] as String, revealCode: row['reveal_code'] as String);
  }

  /// Anonymous private reveal lookup via the secured RPC.
  static Future<AssignmentReveal> getAssignmentByRevealCode(
    String revealCode,
  ) async {
    final rows = await _client.rpc(
      'get_assignment_by_reveal_code',
      params: {'p_reveal_code': revealCode},
    );
    if (rows == null || (rows as List).isEmpty) {
      throw Exception('No participant found for this reveal code.');
    }
    return AssignmentReveal.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Organizer-only: runs the draw client-side, then persists every
  /// assignment via the RLS-protected participants table.
  static Future<void> drawAndAssign(String groupId) async {
    final participants = await forGroup(groupId);
    final assignment = drawAssignments(participants);
    if (assignment == null) {
      throw Exception(
        'Could not generate a valid draw for this group. Need at least 2 participants.',
      );
    }
    final byId = {for (final p in participants) p.id: p};

    for (final entry in assignment.entries) {
      final giverId = entry.key;
      final recipient = byId[entry.value]!;
      await _client.from('participants').update({
        'assigned_to_id': recipient.id,
        'assigned_to_name': recipient.name,
      }).eq('id', giverId);
    }
  }
}
