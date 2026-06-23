import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.card_giftcard, size: 72, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Secret Santa Organizer',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Plan a gift exchange, invite friends with a link, '
                    'and let everyone privately reveal who they\'re gifting.',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  const _FeatureRow(
                    icon: Icons.link,
                    text: 'No accounts needed for participants - just share a link',
                  ),
                  const _FeatureRow(
                    icon: Icons.shuffle,
                    text: 'Fair, gender-aware draw with no self-assignment',
                  ),
                  const _FeatureRow(
                    icon: Icons.lock_outline,
                    text: 'Private reveal codes, full reveal unlocked on event day',
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: () => context.go('/sign-in'),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      child: Text('Sign In / Register'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.go('/join'),
                    child: const Text('I have an invite link or reveal code'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
