import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/group.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<List<Group>> _organizedFuture;
  late Future<List<Group>> _joinedFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _organizedFuture = GroupService.myGroups();
      _joinedFuture = GroupService.myParticipatingGroups();
    });
  }

  Future<void> _deleteGroup(Group group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text(
          '"${group.name}" and all its participants will be permanently deleted. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await GroupService.delete(group.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await AuthService.signOut();
              if (context.mounted) context.go('/');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/create');
          _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Group'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Organizing', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _GroupList(
              future: _organizedFuture,
              emptyText: 'No groups yet. Tap "New Group" to start one.',
              onTap: (group) async {
                await context.push('/group/${group.id}');
                _refresh();
              },
              onDelete: _deleteGroup,
            ),
            const SizedBox(height: 24),
            Text('Participating in', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _GroupList(
              future: _joinedFuture,
              emptyText: 'You haven\'t joined any other groups yet.',
              onTap: (group) async {
                await context.push('/event/${group.id}');
                _refresh();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupList extends StatelessWidget {
  final Future<List<Group>> future;
  final String emptyText;
  final void Function(Group group) onTap;
  final void Function(Group group)? onDelete;

  const _GroupList({
    required this.future,
    required this.emptyText,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Group>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red));
        }
        final groups = snapshot.data ?? [];
        if (groups.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(emptyText),
          );
        }
        return Column(
          children: groups
              .map((group) => Card(
                    child: ListTile(
                      title: Text(group.name),
                      subtitle: Text(
                        '${DateFormat.yMMMd().format(group.eventDate)} - '
                        '${group.budget.toStringAsFixed(0)} ${group.currency} - '
                        '${groupStatusToString(group.status)}',
                      ),
                      trailing: onDelete == null
                          ? const Icon(Icons.chevron_right)
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Delete group',
                                  onPressed: () => onDelete!(group),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                      onTap: () => onTap(group),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}
