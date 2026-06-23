import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/participant.dart';
import '../models/public_group_info.dart';
import '../services/auth_service.dart';
import '../services/email_service.dart';
import '../services/group_service.dart';
import '../services/participant_service.dart';
import '../widgets/install_app_button.dart';

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

/// Account-based join flow: shows the group preview, then either prompts
/// sign-in/registration (no account yet) or - once signed in - auto-joins
/// (or shows a short profile form on first visit) and lands the user
/// straight on their event view. The invite code travels entirely via the
/// URL; nothing here ever asks the user to type a code.
class _JoinForm extends StatefulWidget {
  final String shareCode;

  const _JoinForm({required this.shareCode});

  @override
  State<_JoinForm> createState() => _JoinFormState();
}

class _JoinFormState extends State<_JoinForm> {
  PublicGroupInfo? _groupInfo;
  Participant? _myParticipation;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    PublicGroupInfo? info;
    try {
      info = await GroupService.getPublicByShareCode(widget.shareCode);
    } catch (e) {
      setState(() => _error = 'Invite link is invalid or expired.');
      setState(() => _isLoading = false);
      return;
    }
    try {
      Participant? mine;
      if (AuthService.isSignedIn) {
        mine = await ParticipantService.getMyParticipation(info.id);
      }
      setState(() {
        _groupInfo = info;
        _myParticipation = mine;
      });
      if (mine != null && mounted) {
        context.go('/event/${info.id}');
      }
    } catch (e) {
      setState(() {
        _groupInfo = info;
        _error = e.toString();
      });
    } finally {
      setState(() => _isLoading = false);
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

    if (!AuthService.isSignedIn) {
      return _InlineSignIn(group: group, onAuthenticated: _load);
    }

    if (_myParticipation != null) {
      // _load() already navigates away in this case; show a brief spinner
      // while that completes.
      return const Center(child: CircularProgressIndicator());
    }

    if (group.status != 'draft') {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This group has already drawn names and is no longer accepting new participants.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return _ProfileForm(
      group: group,
      onJoined: (groupId) => context.go('/event/$groupId'),
      onError: (e) => setState(() => _error = e),
      error: _error,
    );
  }
}

/// Shown when a visitor taps an invite link but isn't signed in yet.
/// Sign-in/registration happens inline so the invite code in the URL is
/// never lost to a separate navigation round-trip.
class _InlineSignIn extends StatefulWidget {
  final PublicGroupInfo group;
  final VoidCallback onAuthenticated;

  const _InlineSignIn({required this.group, required this.onAuthenticated});

  @override
  State<_InlineSignIn> createState() => _InlineSignInState();
}

class _InlineSignInState extends State<_InlineSignIn> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegistering = false;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      if (_isRegistering) {
        await AuthService.signUp(_emailController.text.trim(), _passwordController.text);
      } else {
        await AuthService.signIn(_emailController.text.trim(), _passwordController.text);
      }
      widget.onAuthenticated();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'You\'ve been invited to "${group.name}"',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in or create an account to join - you\'ll land straight in the event, no code to type.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'At least 6 characters' : null,
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
                        : Text(_isRegistering ? 'Create account & join' : 'Sign in & join'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isRegistering = !_isRegistering),
                  child: Text(
                    _isRegistering
                        ? 'Already have an account? Sign in'
                        : 'New here? Create an account',
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

/// Short one-time profile form shown after sign-in, before joining a group
/// for the first time.
class _ProfileForm extends StatefulWidget {
  final PublicGroupInfo group;
  final void Function(String groupId) onJoined;
  final void Function(String error) onError;
  final String? error;

  const _ProfileForm({
    required this.group,
    required this.onJoined,
    required this.onError,
    required this.error,
  });

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _wishlistController = TextEditingController();
  Gender _gender = Gender.other;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _wishlistController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final userId = AuthService.currentUser!.id;
      await ParticipantService.joinAsAuthenticatedUser(
        groupId: widget.group.id,
        name: _nameController.text.trim(),
        gender: _gender,
        userId: userId,
        email: AuthService.currentUser?.email,
        wishlist: _wishlistController.text.trim().isEmpty ? null : _wishlistController.text.trim(),
      );
      EmailService.notifyOrganizerOfJoin(widget.group.id, _nameController.text.trim());
      widget.onJoined(widget.group.id);
    } catch (e) {
      widget.onError(e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
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
                if (widget.error != null) ...[
                  Text(widget.error!, style: const TextStyle(color: Colors.red)),
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
                  const SizedBox(height: 24),
                  const InstallAppButton(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
