import '../models/group.dart';
import '../models/public_group_info.dart';
import '../utils/codes.dart';
import 'supabase_service.dart';

class GroupService {
  static final _client = SupabaseService.client;

  static Future<List<Group>> myGroups() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('groups')
        .select()
        .eq('organizer_id', userId)
        .order('created_at', ascending: false);
    return rows.map((row) => Group.fromJson(row)).toList();
  }

  static Future<Group> getById(String id) async {
    final row = await _client.from('groups').select().eq('id', id).single();
    return Group.fromJson(row);
  }

  /// Public lookup for the join page - anonymous, no RLS table access.
  static Future<PublicGroupInfo> getPublicByShareCode(String shareCode) async {
    final rows = await _client.rpc(
      'get_group_by_share_code',
      params: {'p_share_code': shareCode},
    );
    if (rows == null || (rows as List).isEmpty) {
      throw Exception('Group not found for this invite code.');
    }
    return PublicGroupInfo.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Resolves a share code to a group id for an authenticated visitor about
  /// to join - distinct from getPublicByShareCode because this is used once
  /// we already know who they are and just need the id to join/view with.
  static Future<String> getGroupIdByShareCode(String shareCode) async {
    final id = await _client.rpc(
      'get_group_id_by_share_code',
      params: {'p_share_code': shareCode},
    );
    if (id == null) {
      throw Exception('Group not found for this invite code.');
    }
    return id as String;
  }

  /// Groups the signed-in user has joined as a participant (not organized).
  static Future<List<Group>> myParticipatingGroups() async {
    final userId = _client.auth.currentUser!.id;
    final participantRows = await _client
        .from('participants')
        .select('group_id')
        .eq('user_id', userId);
    final groupIds = participantRows.map((row) => row['group_id'] as String).toSet();
    if (groupIds.isEmpty) return [];

    final rows = await _client
        .from('groups')
        .select()
        .inFilter('id', groupIds.toList())
        .order('created_at', ascending: false);
    return rows.map((row) => Group.fromJson(row)).toList();
  }

  /// Full reveal of every assignment in a group, only available after the
  /// event date. Backed by a SECURITY DEFINER function that enforces the
  /// date check server-side.
  static Future<List<GroupRevealEntry>> getGroupReveal(String shareCode) async {
    final rows = await _client.rpc(
      'get_group_reveal',
      params: {'p_share_code': shareCode},
    );
    return (rows as List)
        .map((row) => GroupRevealEntry.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<Group> create({
    required String name,
    required double budget,
    required DateTime eventDate,
    String currency = 'UGX',
    String? description,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final group = Group(
      id: '',
      organizerId: userId,
      name: name,
      budget: budget,
      currency: currency,
      eventDate: eventDate,
      description: description,
      shareCode: generateShareCode(),
      createdAt: DateTime.now(),
    );
    final row =
        await _client.from('groups').insert(group.toInsertJson()).select().single();
    return Group.fromJson(row);
  }

  static Future<void> updateStatus(String groupId, GroupStatus status) async {
    await _client
        .from('groups')
        .update({'status': groupStatusToString(status)})
        .eq('id', groupId);
  }
}
