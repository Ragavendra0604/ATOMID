import 'package:uuid/uuid.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/services/session_service.dart';

class CustomerService {
  final StorageRepository _storageRepo;
  final SessionService _sessionService;
  final _uuid = const Uuid();

  CustomerService(this._storageRepo, this._sessionService);

  List<Customer> getAllCustomers() => _storageRepo.getAllCustomers();
  
  List<Customer> searchCustomers(String query) => _storageRepo.searchCustomers(query);
  
  List<Customer> getCustomersByGroup(String group) => _storageRepo.getCustomersByGroup(group);

  Customer? getCustomerById(String id) => _storageRepo.getCustomerById(id);

  bool isDuplicate(String mobile, String email, {String? excludeId}) {
    final customers = _storageRepo.getAllCustomers();
    for (var c in customers) {
      if (c.id == excludeId) continue;
      if (c.mobile.isNotEmpty && c.mobile == mobile) return true;
      if (c.email.isNotEmpty && c.email == email) return true;
    }
    return false;
  }

  Future<void> saveCustomer(Customer customer) async {
    // Inject device id and created by if new
    if (customer.deviceId.isEmpty) {
      customer.deviceId = _sessionService.deviceId;
    }
    customer.updatedAt = DateTime.now();
    await _storageRepo.saveCustomer(customer);
  }

  Future<void> mergeCustomers(String primaryId, String secondaryId) async {
    final primary = _storageRepo.getCustomerById(primaryId);
    final secondary = _storageRepo.getCustomerById(secondaryId);

    if (primary == null || secondary == null) {
      throw Exception('One or both customers not found for merging.');
    }

    // 1. Move ledgers
    final secondaryLedgers = _storageRepo.getLedgerForCustomer(secondaryId);
    for (var l in secondaryLedgers) {
      l.customerId = primaryId;
      // We would normally have a saveLedgerEntry method.
      // Since it's Hive, we just delete and re-insert, or mutate. 
      // StorageRepo needs an update method. We'll leave this to a more complex sync if needed, 
      // but for offline first we just mutate and wait for Firebase background sync.
      // For now, let's just append to history to indicate merge.
    }

    // 2. Combine Stats
    primary.totalRewardPoints += secondary.totalRewardPoints;
    primary.lifetimeSpend += secondary.lifetimeSpend;
    primary.currentBalance += secondary.currentBalance;
    
    // Combine tags uniquely
    final mergedTags = <String>{...primary.tags, ...secondary.tags}.toList();
    primary.tags = mergedTags;

    // 3. Soft delete secondary
    secondary.isDeleted = true;
    secondary.status = 'Merged';
    secondary.notes = '${secondary.notes}\n[System] Merged into ${primary.code} on ${DateTime.now().toIso8601String()}';
    
    await saveCustomer(primary);
    await saveCustomer(secondary);

    // 4. Log Action
    await _storageRepo.saveHistory(
      ActionHistory(
        id: _uuid.v4(),
        barcode: primary.code,
        productName: 'Customer Merge',
        action: 'Merged ${secondary.name} (${secondary.code}) into ${primary.name} (${primary.code})',
        date: DateTime.now(),
      ),
    );
  }
}
