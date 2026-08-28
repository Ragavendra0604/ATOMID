import 'dart:io';

import 'package:hive_ce_flutter/hive_flutter.dart';

import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';

/// Spins up a real [StorageRepository] on a throwaway Hive directory.
///
/// The repository owns the behaviour that actually breaks — ledger balances,
/// document numbering, the sync queue, stock movement — so the tests that
/// matter exercise it for real rather than mocking it away.
class TestStore {
  final StorageRepository repository;
  final Directory directory;

  TestStore._(this.repository, this.directory);

  /// Pass [repository] to substitute a subclass that fails on demand, for
  /// tests that need a write to blow up part way through a transaction.
  /// Opens an empty store — a fresh install, with nothing configured.
  ///
  /// GST refuses to guess where the shop is, so a store with no company
  /// cannot bill at all. That is correct on a fresh install and the wrong
  /// starting point for a test about billing, so those pass
  /// `configureShop: true`. It stays opt-in because seeding a company also
  /// queues a sync record, which the sync tests count.
  static Future<TestStore> open({
    StorageRepository? repository,
    bool configureShop = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp('atomid_test_');

    final repo = repository ?? StorageRepository();
    await repo.init(storagePath: directory.path);
    repo.deviceId = 'dev_test_abcd';

    if (configureShop) {
      await repo.saveCompany(
        CompanyModel(
          name: 'Atomid Store',
          gstNumber: '33AAAAA0000A1Z5',
          state: 'Tamil Nadu',
          stateCode: '33',
        ),
      );
    }

    return TestStore._(repo, directory);
  }

  Future<void> close() async {
    await repository.dispose();
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  // --- Fixtures -------------------------------------------------------------

  Future<Product> addProduct({
    String name = 'Test Shirt',
    String code = 'TS-1',
    String barcode = 'BC-1',
    double price = 100,
    int quantity = 10,
    int reorderLevel = 3,
    double? gstRate,
  }) async {
    final product = Product(
      id: Ids.generate(),
      productName: name,
      productCode: code,
      category: 'General',
      brand: 'Brand',
      color: 'Red',
      gstTreatment: 'TAXABLE',
      gstRate: gstRate ?? 0.0,
      createdDate: DateTime.now(),
      updatedDate: DateTime.now(),
      variants: [
        ProductVariant(
          size: 'M',
          price: price,
          quantity: quantity,
          barcode: barcode,
          reorderLevel: reorderLevel,
        ),
      ],
    );
    await repository.saveProduct(product);
    return product;
  }

  Future<Customer> addCustomer({
    String name = 'Asha',
    String mobile = '9000000001',
    double creditLimit = 0,
    double points = 0,
  }) async {
    final customer = Customer(
      id: Ids.generate(),
      code: 'C-1',
      name: name,
      mobile: mobile,
      createdDate: DateTime.now(),
      creditLimit: creditLimit,
      totalRewardPoints: points,
    );
    await repository.saveCustomer(customer);
    return customer;
  }

  /// A supplier in the shop's own state unless told otherwise.
  ///
  /// The state is not decoration: purchase GST refuses to guess where a
  /// supplier is, so a fixture without one cannot be taxed at all.
  Future<Supplier> addSupplier({
    String name = 'Acme Textiles',
    String state = 'Tamil Nadu',
    String stateCode = '33',
    String gstNumber = '',
  }) async {
    final supplier = Supplier(
      id: Ids.generate(),
      supplierCode: 'S-1',
      supplierName: name,
      phone: '9000000002',
      state: state,
      stateCode: stateCode,
      gstNumber: gstNumber,
      createdDate: DateTime.now(),
      updatedDate: DateTime.now(),
    );
    await repository.saveSupplier(supplier);
    return supplier;
  }
}
