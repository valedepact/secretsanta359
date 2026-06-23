import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/participant.dart';
import '../models/public_group_info.dart';
import '../services/group_service.dart';
import '../services/participant_service.dart';

class JoinPage extends StatefulWidget {
  final String? shareCode;
  final String? revealCode;

  const JoinPage({super.key, this.shareCode, this.revealCode});

  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  @override
  Widget build(BuildContext context) {
    if (widget.revealCode != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your Secret Santa')),
        body: _RevealView(revealCode: widget.revealCode!),
      );
    }
    if (widget.shareCode != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Join Group')),
        body: _JoinForm(shareCode: widget.shareCode!),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Join / Reveal')),
      body: const _ManualCodeEntry(),
    );
  }
}

class _ManualCodeEntry extends StatefulWidget {
  const _ManualCodeEntry();

  @override
  State<_ManualCodeEntry> createState() => _ManualCodeEntryState();
}

class _ManualCodeEntryState extends State<_ManualCodeEntry> {
  final _inviteController = TextEditingController();
  final _revealController = TextEditingController();

  @override
  void dispose() {
    _inviteController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter an invite code', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _inviteController,
                decoration: const InputDecoration(labelText: 'Invite code'),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  final code = _inviteController.text.trim();
                  if (code.isNotEmpty) context.go('/join?code=$code');
                },
                child: const Text('Join'),
              ),
              const SizedBox(height: 32),
              Text('Or enter your personal reveal code', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _revealController,
                decoration: const InputDecoration(labelText: 'Reveal code'),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  final code = _revealController.text.trim();
                  if (code.isNotEmpty) context.go('/join?reveal=$code');
                },
                child: const Text('Reveal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinForm extends StatefulWidget {
  final String shareCode;

  const _JoinForm({required this.shareCode});

  @override
  State<_JoinForm> createState() => _JoinFormState();
}

class _JoinFormState extends State<_JoinForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _wishlistController = TextEditingController();
  Gender _gender = Gender.other;
  PublicGroupInfo? _groupInfo;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  JoinResult? _joinResult;

  @override
  void initState() {
    super.initState();
    _loadGroup();
  }

  Future<void> _loadGroup() async {
    try {
      final info = await GroupService.getPublicByShareCode(widget.shareCode);
      setState(() => _groupInfo = info);
    } catch (e) {
      setState(() => _error = 'Invite link is invalid or expired.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _wishlistController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final result = await ParticipantService.join(
        groupId: _groupInfo!.id,
        name: _nameController.text.trim(),
        gender: _gender,
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        wishlist: _wishlistController.text.trim().isEmpty ? null : _wishlistController.text.trim(),
      );
      setState(() => _joinResult = result);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _groupInfo == null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    final group = _groupInfo!;

    if (_joinResult != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 64),
                const SizedBox(height: 16),
                Text('You\'re in, ${_nameController.text.trim()}!',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                const Text('Save your personal reveal code. Use it after the event date to see who you\'re gifting.'),
                const SizedBox(height: 16),
                SelectableText(
                  _joinResult!.revealCode,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (group.status != 'draft') {
      return Center(
        child: Text(
          'This group has already drawn names and is no longer accepting new participants.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(group.name, style: Theme.of(context).textTheme.headlineSmall),
                Text(
                  'Budget: ${group.budget.toStringAsFixed(0)} ${group.currency} - '
                  'Event date: ${DateFormat.yMMMd().format(group.eventDate)}',
                ),
                if (group.description != null) ...[
                  const SizedBox(height: 8),
                  Text(group.description!),
                ],
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Your name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Gender>(
                  initialValue: _gender,
                  decoration: const InputDecoration(labelText: 'Gender'),
                  items: const [
                    DropdownMenuItem(value: Gender.female, child: Text('Female')),
                    DropdownMenuItem(value: Gender.male, child: Text('Male')),
                    DropdownMenuItem(value: Gender.other, child: Text('Other / prefer not to say')),
                  ],
                  onChanged: (v) => setState(() => _gender = v ?? Gender.other),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email (optional, for reveal notification)'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _wishlistController,
                  decoration: const InputDecoration(labelText: 'Wishlist (optional)'),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Join Group'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RevealView extends StatefulWidget {
  final String revealCode;

  const _RevealView({required this.revealCode});

  @override
  State<_RevealView> createState() => _RevealViewState();
}

class _RevealViewState extends State<_RevealView> {
  late Future<AssignmentReveal> _future;

  @override
  void initState() {
    super.initState();
    _future = ParticipantService.getAssignmentByRevealCode(widget.revealCode);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssignmentReveal>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Reveal code not found. Double check the code and try again.',
              textAlign: TextAlign.center,
            ),
          );
        }
        final reveal = snapshot.data!;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.card_giftcard, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Hi ${reveal.participantName}!', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('In ${reveal.groupName}, you are gifting:'),
                  const SizedBox(height: 12),
                  Text(
                    reveal.assignedToName ?? 'Not drawn yet - check back later.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
