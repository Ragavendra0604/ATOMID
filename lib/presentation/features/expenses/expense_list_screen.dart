import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/providers/provider_refresh_helper.dart';
import 'package:atomid/presentation/features/expenses/expense_form_screen.dart';
import 'package:atomid/data/models/expense_model.dart';

class ExpenseListScreen extends ConsumerStatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  ConsumerState<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends ConsumerState<ExpenseListScreen> {
  String _selectedPeriod = 'This Month';

  @override
  void initState() {
    super.initState();
    // Seed default categories if none exist
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(expenseServiceProvider).seedDefaultCategories();
      ProviderRefreshHelper.invalidateExpenseProviders(ref);
    });
  }

  List<Expense> _filterExpenses(List<Expense> expenses) {
    final now = DateTime.now();
    return expenses.where((e) {
      if (_selectedPeriod == 'Today') {
        return e.date.year == now.year && e.date.month == now.month && e.date.day == now.day;
      } else if (_selectedPeriod == 'This Week') {
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        return e.date.isAfter(startOfWeek.subtract(const Duration(days: 1)));
      } else if (_selectedPeriod == 'This Month') {
        return e.date.year == now.year && e.date.month == now.month;
      }
      return true; // All Time
    }).toList();
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'home': return Icons.home;
      case 'electric_bolt': return Icons.electric_bolt;
      case 'people': return Icons.people;
      case 'build': return Icons.build;
      case 'campaign': return Icons.campaign;
      case 'receipt': return Icons.receipt;
      default: return Icons.receipt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final expenses = ref.watch(expensesProvider);
    final filteredExpenses = _filterExpenses(expenses);
    final settings = ref.watch(settingsProvider);
    final categories = ref.watch(expenseCategoriesProvider);

    final totalAmount = filteredExpenses.fold(0.0, (sum, e) => sum + e.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (val) => setState(() => _selectedPeriod = val),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'Today', child: Text('Today')),
              const PopupMenuItem(value: 'This Week', child: Text('This Week')),
              const PopupMenuItem(value: 'This Month', child: Text('This Month')),
              const PopupMenuItem(value: 'All Time', child: Text('All Time')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary Header
          Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            color: Theme.of(context).primaryColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Expenses ($_selectedPeriod)',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  '${settings.currencySymbol}${totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: filteredExpenses.isEmpty
                ? const Center(child: Text('No expenses found for this period.'))
                : ListView.builder(
                    itemCount: filteredExpenses.length,
                    itemBuilder: (context, index) {
                      final expense = filteredExpenses[index];
                      // Find category to get icon
                      final cat = categories.firstWhere(
                        (c) => c.id == expense.categoryId,
                        orElse: () => ExpenseCategory(id: '', name: 'Unknown'),
                      );

                      return Dismissible(
                        key: Key(expense.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Expense?'),
                              content: const Text('Are you sure you want to delete this expense?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                              ],
                            ),
                          );
                        },
                        onDismissed: (direction) async {
                          await ref.read(expenseServiceProvider).deleteExpense(expense.id);
                          ProviderRefreshHelper.invalidateExpenseProviders(ref);
                        },
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                            child: Icon(_getIconData(cat.iconName), color: Theme.of(context).primaryColor),
                          ),
                          title: Text(expense.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${expense.categoryName} • ${expense.date.month}/${expense.date.day}/${expense.date.year}'),
                          trailing: Text(
                            '-${settings.currencySymbol}${expense.amount.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => ExpenseFormScreen(expense: expense)),
                            );
                          },
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
            MaterialPageRoute(builder: (_) => const ExpenseFormScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
