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
  late Future<List<Group>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _groupsFuture = GroupService.myGroups();
  }

  void _refresh() {
    setState(() => _groupsFuture = GroupService.myGroups());
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
      body: FutureBuilder<List<Group>>(
        future: _groupsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final groups = snapshot.data ?? [];
          if (groups.isEmpty) {
            return const Center(
              child: Text('No groups yet. Tap "New Group" to start one.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return Card(
                child: ListTile(
                  title: Text(group.name),
                  subtitle: Text(
                    '${DateFormat.yMMMd().format(group.eventDate)} - '
                    '${group.budget.toStringAsFixed(0)} ${group.currency} - '
                    '${groupStatusToString(group.status)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await context.push('/group/${group.id}');
                    _refresh();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
