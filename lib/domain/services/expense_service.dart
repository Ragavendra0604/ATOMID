import 'package:atomid/data/models/expense_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';

class ExpenseService {
  final StorageRepository _storageRepo;

  ExpenseService(this._storageRepo);

  List<Expense> getAllExpenses() {
    return _storageRepo.getExpenses();
  }

  List<ExpenseCategory> getExpenseCategories() {
    return _storageRepo.getExpenseCategories();
  }

  Future<void> saveExpense(Expense expense, {bool isNew = false}) async {
    await _storageRepo.saveExpense(expense, isNew: isNew);
  }

  Future<void> deleteExpense(String expenseId) async {
    await _storageRepo.deleteExpense(expenseId);
  }

  Future<void> saveExpenseCategory(ExpenseCategory category) async {
    await _storageRepo.saveExpenseCategory(category);
  }

  Future<void> deleteExpenseCategory(String categoryId) async {
    await _storageRepo.deleteExpenseCategory(categoryId);
  }

  // Pre-seed some default categories if empty
  Future<void> seedDefaultCategories() async {
    final existing = getExpenseCategories();
    if (existing.isEmpty) {
      final defaultCategories = [
        ExpenseCategory(id: 'cat_rent', name: 'Rent', iconName: 'home'),
        ExpenseCategory(
          id: 'cat_utilities',
          name: 'Utilities',
          iconName: 'electric_bolt',
        ),
        ExpenseCategory(id: 'cat_salary', name: 'Salary', iconName: 'people'),
        ExpenseCategory(
          id: 'cat_maintenance',
          name: 'Maintenance',
          iconName: 'build',
        ),
        ExpenseCategory(
          id: 'cat_marketing',
          name: 'Marketing',
          iconName: 'campaign',
        ),
        ExpenseCategory(id: 'cat_other', name: 'Other', iconName: 'receipt'),
      ];

      for (var cat in defaultCategories) {
        await saveExpenseCategory(cat);
      }
    }
  }
}
