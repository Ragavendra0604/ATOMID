// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/data/repositories/storage_repository.dart';

void main() {
  test('Verify all local data', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final repo = StorageRepository();

    // Use dart:io to bypass path_provider plugin channels in tests
    final dbPath = r'C:\Users\HARIRAGAVENDRA\AppData\Roaming\atomid\atomid\db';

    print('USING DB PATH: $dbPath');

    await repo.init(storagePath: dbPath);

    print('=====================================');
    print('DATABASE VERIFICATION REPORT');
    print('=====================================');
    print('Products: ${repo.getAllProducts().length}');
    print('Customers: ${repo.getAllCustomers().length}');
    print('Sales (Invoices): ${repo.getAllSales().length}');
    print('Suppliers: ${repo.getSuppliers().length}');
    print('Purchases: ${repo.getPurchases().length}');
    print('Expenses: ${repo.getExpenses().length}');
    print('-------------------------------------');
    print('SYNC STATUS');
    print('Pending Items: ${repo.getPendingSyncItems().length}');
    print('Failed Items: ${repo.getDeadSyncItems().length}');
    print('Total Sync Logs: ${repo.getSyncLogs().length}');
    print('=====================================');

    await repo.dispose();
  });
}
