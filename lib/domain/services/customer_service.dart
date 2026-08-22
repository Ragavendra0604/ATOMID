import 'package:uuid/uuid.dart';
import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/customer_stats.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/services/session_service.dart';

class CustomerService {
  final StorageRepository _storageRepo;
  final SessionService _sessionService;
  final _uuid = const Uuid();

  CustomerService(this._storageRepo, this._sessionService);

  List<Customer> getAllCustomers() => _storageRepo.getAllCustomers();

  List<Customer> searchCustomers(String query) =>
      _storageRepo.searchCustomers(query);

  List<Customer> getCustomersByGroup(String group) =>
      _storageRepo.getCustomersByGroup(group);

  Customer? getCustomerById(String id) => _storageRepo.getCustomerById(id);

  /// The till's primary lookup: who is this phone number?
  Customer? findByMobile(String mobile) =>
      _storageRepo.getCustomerByMobile(mobile);

  /// How often this person has bought, and how much.
  CustomerVisitStats statsFor(String customerId) =>
      _storageRepo.getCustomerStats(customerId);

  /// Registers a walk-in from their phone number alone.
  ///
  /// Everything else is optional — capturing the number is what makes them
  /// recognisable on the next visit, and a cashier at a queue will not type
  /// more than that.
  Future<Customer> registerByMobile(String mobile, {String name = ''}) async {
    final digits = StorageRepository.normaliseMobile(mobile);
    if (digits.length < 10) {
      throw const AppException('Enter a 10-digit mobile number.');
    }

    final existing = _storageRepo.getCustomerByMobile(digits);
    if (existing != null) return existing;

    final customer = Customer(
      id: _uuid.v4(),
      code: 'C-${digits.substring(digits.length - 6)}',
      name: name.trim().isEmpty ? 'Customer $digits' : name.trim(),
      mobile: digits,
      createdDate: DateTime.now(),
      deviceId: _sessionService.deviceId,
      updatedAt: DateTime.now(),
    );

    await _storageRepo.saveCustomer(customer);
    return customer;
  }

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

    // 1. Combine stats. Balance is deliberately not touched here — it is
    // derived from the ledger below, so it can never drift from what the
    // ledger detail actually shows.
    //
    // Reward points are left alone here for the same reason, and it is not
    // the same reason as lifetime spend. `lifetimeSpend` is a running figure
    // nothing recomputes, so adding the two is the only way to carry it over.
    // `totalRewardPoints` is derived from the loyalty ledger, so adding the
    // two here would be overwritten by the next recomputation; step 2b moves
    // the rows across instead, and the derivation picks them up.
    primary.lifetimeSpend += secondary.lifetimeSpend;

    // Combine tags uniquely
    final mergedTags = <String>{...primary.tags, ...secondary.tags}.toList();
    primary.tags = mergedTags;
    await saveCustomer(primary);

    // 2. Move every ledger line (and any opening balance) to the primary
    // account, and settle both running balances from that ledger.
    await _storageRepo.reassignCustomerLedger(
      fromCustomerId: secondaryId,
      toCustomerId: primaryId,
    );

    // 2b. Same again for the loyalty ledger, so the primary's derived point
    // balance accounts for what the secondary earned.
    await _storageRepo.reassignLoyaltyTransactions(
      fromCustomerId: secondaryId,
      toCustomerId: primaryId,
    );

    // 3. Soft delete secondary.
    //
    // Re-read first: steps 2 and 2b both recompute and save the secondary's
    // derived figures, and writing back the copy fetched before them would
    // undo that.
    final merged = _storageRepo.getCustomerById(secondaryId) ?? secondary;
    merged.isDeleted = true;
    merged.status = 'Merged';
    merged.notes =
        '${merged.notes}\n[System] Merged into ${primary.code} on ${DateTime.now().toIso8601String()}';
    await saveCustomer(merged);

    // 4. Log Action
    await _storageRepo.saveHistory(
      ActionHistory(
        id: _uuid.v4(),
        barcode: primary.code,
        productName: 'Customer Merge',
        action:
            'Merged ${secondary.name} (${secondary.code}) into ${primary.name} (${primary.code})',
        date: DateTime.now(),
      ),
    );
  }
}
