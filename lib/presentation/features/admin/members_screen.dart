import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'member_form_screen.dart';

class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  String _searchQuery = '';
  bool _showDeleted = false;

  @override
  Widget build(BuildContext context) {
    var employees = ref.watch(employeesProvider);

    employees = employees.where((e) {
      if (!_showDeleted && e.isDeleted) return false;
      if (_searchQuery.isNotEmpty) {
        return e.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            e.email.toLowerCase().contains(_searchQuery.toLowerCase());
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          IconButton(
            icon: Icon(_showDeleted ? Icons.visibility : Icons.visibility_off),
            tooltip: _showDeleted ? 'Hide Deleted' : 'Show Deleted',
            onPressed: () {
              setState(() {
                _showDeleted = !_showDeleted;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search members...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),
          Expanded(
            child: employees.isEmpty
                ? const Center(child: Text('No members found.'))
                : ListView.builder(
                    itemCount: employees.length,
                    itemBuilder: (context, index) {
                      final employee = employees[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: employee.isActive
                              ? Colors.blue
                              : Colors.grey,
                          child: Text(
                            employee.fullName.substring(0, 1).toUpperCase(),
                          ),
                        ),
                        title: Text(
                          employee.fullName,
                          style: TextStyle(
                            decoration: employee.isDeleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          '${employee.role.name} • ${employee.email}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        MemberFormScreen(employee: employee),
                                  ),
                                ).then((_) => ref.refresh(employeesProvider));
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MemberFormScreen()),
          ).then((_) => ref.refresh(employeesProvider));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
