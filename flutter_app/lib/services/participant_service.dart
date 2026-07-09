import '../models/participant.dart';
import '../models/public_group_info.dart';
import '../utils/draw_algorithm.dart';
import 'supabase_service.dart';

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

  /// Authenticated join: inserts a participant row linked to the signed-in
  /// user via RLS (no RPC needed - the insert policy already enforces the
  /// group must still be a draft). Returns the new participant.
  static Future<Participant> joinAsAuthenticatedUser({
    required String groupId,
    required String name,
    required Gender gender,
    required String userId,
    String? email,
    String? wishlist,
  }) async {
    final row = await _client
        .from('participants')
        .insert({
          'group_id': groupId,
          'name': name,
          'gender': genderToString(gender),
          'email': email,
          'wishlist': wishlist,
          'user_id': userId,
        })
        .select()
        .single();
    return Participant.fromJson(row);
  }

  /// Returns the signed-in user's own participant row for a group, or null
  /// if they haven't joined it. RLS-protected (only their own rows).
  static Future<Participant?> getMyParticipation(String groupId) async {
    final row = await _client
        .from('participants')
        .select()
        .eq('group_id', groupId)
        .eq('user_id', _client.auth.currentUser!.id)
        .maybeSingle();
    return row == null ? null : Participant.fromJson(row);
  }

  /// All of the signed-in user's own participant rows, across every group
  /// they've joined - used to build the "events I'm participating in"
  /// section of the dashboard.
  static Future<List<Participant>> myParticipations() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('participants')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows.map((row) => Participant.fromJson(row)).toList();
  }

  /// Updates the signed-in participant's own wishlist. A database trigger
  /// rejects changes to any other column on this row.
  static Future<void> updateMyWishlist(String participantId, String? wishlist) async {
    await _client
        .from('participants')
        .update({'wishlist': wishlist})
        .eq('id', participantId);
  }

  /// Returns the name and current wishlist of the person the signed-in
  /// user is assigned to gift, or null if they haven't been assigned yet.
  /// Uses a SECURITY DEFINER RPC so a giver can read just their own
  /// giftee's wishlist without a broad RLS grant on other participants'
  /// rows.
  static Future<Giftee?> getMyGiftee(String groupId) async {
    final rows = await _client.rpc(
      'get_my_giftee',
      params: {'p_group_id': groupId},
    );
    if (rows == null || (rows as List).isEmpty) return null;
    return Giftee.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Organizer-only: removes a participant from their own group. Only
  /// allowed before a draw - the assigned_to_id foreign key has no cascade,
  /// so deleting a participant who's already part of an assignment chain
  /// would fail; the UI only offers this while the group is still a draft.
  static Future<void> remove(String participantId) async {
    await _client.from('participants').delete().eq('id', participantId);
  }

  /// Organizer-only: computes the draw client-side then writes all
  /// assignments atomically via a single server-side transaction (RPC).
  /// A network interruption can no longer leave the group half-drawn.
  static Future<void> drawAndAssign(String groupId) async {
    final participants = await forGroup(groupId);
    final assignment = drawAssignments(participants);
    if (assignment == null) {
      throw Exception(
        'Could not generate a valid draw for this group. Need at least 2 participants.',
      );
    }
    final byId = {for (final p in participants) p.id: p};

    final payload = assignment.entries.map((e) => {
      'giver_id': e.key,
      'giftee_id': e.value,
      'giftee_name': byId[e.value]!.name,
    }).toList();

    await _client.rpc('perform_draw', params: {
      'p_group_id': groupId,
      'p_assignments': payload,
    });
  }
}
