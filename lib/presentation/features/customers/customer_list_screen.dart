import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'customer_form_screen.dart';
import 'customer_details_screen.dart';

class CustomerListScreen extends ConsumerWidget {
  const CustomerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(filteredCustomersProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exporting Customers...')));
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Import',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import Customers...')));
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by Name, Mobile, Code, Tags...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) {
                    ref.read(customerSearchProvider.notifier).setQuery(val);
                  },
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text('Filter by Group: ', style: TextStyle(color: Colors.white70)),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: ref.watch(customerGroupFilterProvider),
                        dropdownColor: Theme.of(context).cardColor,
                        style: const TextStyle(color: Colors.white),
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'All', child: Text('All')),
                          DropdownMenuItem(value: 'General', child: Text('General')),
                          DropdownMenuItem(value: 'VIP', child: Text('VIP')),
                          DropdownMenuItem(value: 'Wholesale', child: Text('Wholesale')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            ref.read(customerGroupFilterProvider.notifier).setGroup(v);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: customers.isEmpty
          ? const Center(child: Text('No customers found.'))
          : ListView.builder(
              itemCount: customers.length,
              itemBuilder: (context, index) {
                final c = customers[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        c.name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c.code} • ${c.mobile}'),
                        if (c.customerGroup != 'General')
                          Text('Group: ${c.customerGroup}', style: const TextStyle(fontSize: 12, color: Colors.blue)),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${settings.currencySymbol}${c.currentBalance.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: c.currentBalance > 0 ? Colors.red : (c.currentBalance < 0 ? Colors.green : Colors.grey),
                          ),
                        ),
                        Text(
                          c.currentBalance > 0 ? 'Due' : (c.currentBalance < 0 ? 'Advance' : 'Settled'),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CustomerDetailsScreen(customerId: c.id),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CustomerFormScreen()),
          );
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Add Customer'),
      ),
    );
  }
}
