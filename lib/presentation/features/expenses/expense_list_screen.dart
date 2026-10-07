import 'package:flutter/material.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/features/expenses/expense_form_screen.dart';
import 'package:atomid/domain/date_window.dart';
import 'package:atomid/data/models/expense_model.dart';

class ExpenseListScreen extends ConsumerStatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  ConsumerState<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends ConsumerState<ExpenseListScreen> {
  String _selectedPeriod = 'This Month';
  DateTimeRange? _customDateRange;

  @override
  void initState() {
    super.initState();
    // Seed default categories if none exist
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(expenseServiceProvider).seedDefaultCategories();
    });
  }

  List<Expense> _filterExpenses(List<Expense> expenses) {
    if (_selectedPeriod == 'Custom' && _customDateRange != null) {
      final from = DateWindow.startOfDay(_customDateRange!.start);
      final until = DateWindow.startOfDay(
        _customDateRange!.end,
      ).add(const Duration(days: 1));
      final window = DateWindow(from: from, until: until);
      return expenses.where((e) => window.contains(e.date)).toList();
    }
    final window = DateWindow.forTimeframe(_selectedPeriod, DateTime.now());
    if (window == null) return expenses; // All Time
    return expenses.where((e) => window.contains(e.date)).toList();
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'home':
        return Icons.home;
      case 'electric_bolt':
        return Icons.electric_bolt;
      case 'people':
        return Icons.people;
      case 'build':
        return Icons.build;
      case 'campaign':
        return Icons.campaign;
      case 'receipt':
        return Icons.receipt;
      default:
        return Icons.receipt;
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
            onSelected: (val) async {
              if (val == 'Custom') {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDateRange: _customDateRange,
                );
                if (picked != null) {
                  setState(() {
                    _customDateRange = picked;
                    _selectedPeriod = val;
                  });
                }
              } else {
                setState(() => _selectedPeriod = val);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'Today', child: Text('Today')),
              const PopupMenuItem(value: 'This Week', child: Text('This Week')),
              const PopupMenuItem(
                value: 'This Month',
                child: Text('This Month'),
              ),
              const PopupMenuItem(value: 'All Time', child: Text('All Time')),
              const PopupMenuItem(
                value: 'Custom',
                child: Text('Custom Date Range'),
              ),
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
                  'Total Expenses (${_selectedPeriod == 'Custom' && _customDateRange != null ? '${Fmt.date(_customDateRange!.start)} - ${Fmt.date(_customDateRange!.end)}' : _selectedPeriod})',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withValues(alpha: 0.75),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  Fmt.money(totalAmount, settings.currencySymbol),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: filteredExpenses.isEmpty
                ? const Center(
                    child: Text('No expenses found for this period.'),
                  )
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
                              content: const Text(
                                'Are you sure you want to delete this expense?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (direction) async {
                          await ref
                              .read(expenseServiceProvider)
                              .deleteExpense(expense.id);
                        },
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(
                              context,
                            ).primaryColor.withValues(alpha: 0.1),
                            child: Icon(
                              _getIconData(cat.iconName),
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                          title: Text(
                            expense.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${expense.categoryName} · ${Fmt.date(expense.date)}',
                          ),
                          trailing: Text(
                            '-${Fmt.money(expense.amount, settings.currencySymbol)}',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ExpenseFormScreen(expense: expense),
                              ),
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
        heroTag: 'add-expense',
        tooltip: 'Add expense',
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
