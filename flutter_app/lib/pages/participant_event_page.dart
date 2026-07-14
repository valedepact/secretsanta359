import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/group.dart';
import '../models/participant.dart';
import '../services/group_service.dart';
import '../services/participant_service.dart';
import '../utils/friendly_error.dart';

/// What a signed-in participant sees for an event they've joined: group
/// info, their own assignment (once drawn), and a wishlist editor.
class ParticipantEventPage extends StatefulWidget {
  final String groupId;

  const ParticipantEventPage({super.key, required this.groupId});

  @override
  State<ParticipantEventPage> createState() => _ParticipantEventPageState();
}

class _ParticipantEventPageState extends State<ParticipantEventPage> {
  Group? _group;
  Participant? _me;
  Giftee? _giftee;
  bool _isLoading = true;
  bool _isSavingWishlist = false;
  String? _error;
  late TextEditingController _wishlistController;

  @override
  void initState() {
    super.initState();
    _wishlistController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _wishlistController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final group = await GroupService.getById(widget.groupId);
      final me = await ParticipantService.getMyParticipation(widget.groupId);
      final giftee = me != null && me.hasBeenAssigned
          ? await ParticipantService.getMyGiftee(widget.groupId)
          : null;
      setState(() {
        _group = group;
        _me = me;
        _giftee = giftee;
        _wishlistController.text = me?.wishlist ?? '';
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveWishlist() async {
    if (_me == null) return;
    setState(() => _isSavingWishlist = true);
    try {
      await ParticipantService.updateMyWishlist(
        _me!.id,
        _wishlistController.text.trim().isEmpty ? null : _wishlistController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wishlist saved')),
        );
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      setState(() => _isSavingWishlist = false);
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
    final me = _me;

    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.go('/'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            if (me == null)
              const Text('You have not joined this group yet.')
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Budget: ${group.budget.toStringAsFixed(0)} ${group.currency}'),
                      Text('Event date: ${DateFormat.yMMMd().format(group.eventDate)}'),
                      if (group.description != null) ...[
                        const SizedBox(height: 8),
                        Text(group.description!),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your assignment', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        me.hasBeenAssigned
                            ? 'You are gifting: ${me.assignedToName}'
                            : 'Names haven\'t been drawn yet - check back later.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (me.hasBeenAssigned) ...[
                        const SizedBox(height: 12),
                        Text('Their wishlist', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          _giftee?.wishlist?.isNotEmpty == true
                              ? _giftee!.wishlist!
                              : 'They haven\'t added a wishlist yet.',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your wishlist', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _wishlistController,
                        decoration: const InputDecoration(
                          hintText: 'Let your Secret Santa know what you\'d like',
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _isSavingWishlist ? null : _saveWishlist,
                        child: _isSavingWishlist
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save wishlist'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
