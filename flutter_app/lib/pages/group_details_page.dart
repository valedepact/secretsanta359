import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/group.dart';
import '../models/participant.dart';
import '../services/email_service.dart';
import '../services/group_service.dart';
import '../services/participant_service.dart';
import '../utils/app_links.dart';

class GroupDetailsPage extends StatefulWidget {
  final String groupId;

  const GroupDetailsPage({super.key, required this.groupId});

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  Group? _group;
  List<Participant> _participants = [];
  bool _isLoading = true;
  bool _isDrawing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final group = await GroupService.getById(widget.groupId);
      final participants = await ParticipantService.forGroup(widget.groupId);
      setState(() {
        _group = group;
        _participants = participants;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String get _inviteLink => inviteLink(_group!.shareCode);

  Future<void> _copyInviteLink() async {
    await Clipboard.setData(ClipboardData(text: _inviteLink));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite link copied')),
      );
    }
  }

  Future<void> _removeParticipant(Participant participant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove participant?'),
        content: Text('${participant.name} will be removed from this group.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ParticipantService.remove(participant.id);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _draw() async {
    setState(() {
      _isDrawing = true;
      _error = null;
    });
    try {
      await ParticipantService.drawAndAssign(widget.groupId);
      await GroupService.updateStatus(widget.groupId, GroupStatus.drawn);
      // Fire-and-forget: don't block the draw flow on email delivery.
      EmailService.sendRevealEmails(widget.groupId);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isDrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _group == null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }
    final group = _group!;
    final canDraw = group.status == GroupStatus.draft && _participants.length >= 2;

    return Scaffold(
      appBar: AppBar(title: Text(group.name)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Invite participants', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: SelectableText(_inviteLink)),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: _copyInviteLink,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Participants (${_participants.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_participants.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No one has joined yet. Share the invite link above.'),
              )
            else
              ..._participants.map((p) => Card(
                    child: ListTile(
                      title: Text(p.name),
                      subtitle: Text(
                        p.hasBeenAssigned
                            ? 'Reveal code: ${p.revealCode}'
                            : '${genderToString(p.gender)} - ${p.email ?? 'no email'}',
                      ),
                      trailing: p.hasBeenAssigned
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Remove participant',
                              onPressed: () => _removeParticipant(p),
                            ),
                    ),
                  )),
            const SizedBox(height: 24),
            if (group.status == GroupStatus.draft)
              FilledButton(
                onPressed: canDraw && !_isDrawing ? _draw : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _isDrawing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _participants.length < 2
                              ? 'Need at least 2 participants to draw'
                              : 'Draw Names',
                        ),
                ),
              )
            else
              Text(
                group.status == GroupStatus.drawn
                    ? 'Names have been drawn. Reveal unlocks on '
                        '${DateFormat.yMMMd().format(group.eventDate)}'
                    : 'Completed',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
          ],
        ),
      ),
    );
  }
}
