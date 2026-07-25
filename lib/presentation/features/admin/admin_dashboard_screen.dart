import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/widgets/role_guard_widget.dart';
import 'members_screen.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(employeesProvider);
    final activeEmployees = employees.where((e) => e.isActive && !e.isDeleted).length;
    final totalEmployees = employees.where((e) => !e.isDeleted).length;

    return RoleGuard(
      ownerOnly: true,
      fallback: Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(child: Text('Only the Shop Owner can access the Admin Panel.')),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Owner Admin Panel'),
          actions: [
            IconButton(
              icon: const Icon(Icons.people),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MembersScreen()),
                );
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Text(
              'Dashboard',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context,
                    'Total Employees',
                    totalEmployees.toString(),
                    Icons.groups,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    context,
                    'Active Employees',
                    activeEmployees.toString(),
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.people_outline)),
              title: const Text('Manage Members'),
              subtitle: const Text('Add, edit, or remove employees and assign roles.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MembersScreen()),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.security)),
              title: const Text('Activity Logs'),
              subtitle: const Text('View recent actions performed by members.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // TODO: Navigate to Activity Logs Screen
              },
            ),
            const Divider(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
