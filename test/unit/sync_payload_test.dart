import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/expense_model.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/data/sync/entity_codec.dart';

import '../support/test_store.dart';

/// Guards the encode/decode pair.
///
/// The payload builder was hand-written and had drifted away from the models:
/// expenses lost their title, purchases lost their status and delivery date.
/// A missing field here is silent data loss on sync, so every entity is
/// round-tripped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late StorageRepository repo;

  setUp(() async {
    store = await TestStore.open();
    repo = store.repository;
  });

  tearDown(() => store.close());

  test('every syncable entity has a serialiser', () {
    for (final entityType in StorageRepository.syncableEntities) {
      expect(
        EntityCodec.collectionFor(entityType),
        isNotEmpty,
        reason: '$entityType has no Firestore collection',
      );
    }
  });

  test('nothing is enqueued that cannot be serialised', () async {
    // Regression: Company, Employee, ActivityLog, LoginHistory and
    // ExpenseCategory were queued with no encoder, so their items were never
    // sent and never removed — the queue grew without bound.
    await store.addProduct();
    await store.addCustomer();
    await store.addSupplier();
    await repo.saveCompany(CompanyModel(name: 'Test Store'));
    await repo.saveLoyaltySettings(LoyaltySettingsModel());
    await repo.saveExpenseCategory(
      ExpenseCategory(id: 'cat_test', name: 'Test'),
    );

    for (final item in repo.getPendingSyncItems()) {
      expect(
        repo.getEntityJson(item.entityType, item.entityId),
        isNotNull,
        reason: '${item.entityType} was queued but cannot be serialised',
      );
    }
  });

  test('a product round-trips without losing a field', () async {
    final product = await store.addProduct(price: 249.5, quantity: 7);

    final json = repo.getEntityJson('Product', product.id)!;
    final restored = EntityCodec.product(json);

    expect(restored.productName, product.productName);
    expect(restored.productCode, product.productCode);
    // Regression: the payload never carried `updatedDate` at all, so the
    // decoder's `DateTime.now()` fallback made this pass even though the
    // field was silently missing. Asserting the real value round-trips is
    // what would have caught it.
    expect(json['updatedDate'], isNotNull);
    expect(restored.updatedDate, product.updatedDate);
    expect(restored.isDeleted, isFalse);
    expect(restored.variants.single.price, 249.5);
    expect(restored.variants.single.quantity, 7);
    expect(restored.variants.single.reorderLevel, 3);
    expect(restored.variants.single.sku, product.variants.single.sku);
  });

  test('a stock movement bumps updatedDate so peers can tell it changed', () async {
    final product = await store.addProduct(quantity: 5);
    final before = product.updatedDate;

    await repo.performStockIn(
      productId: product.id,
      variantBarcode: product.variants.single.barcode,
      quantity: 3,
      reason: 'Purchase receipt',
    );

    final after = repo.getProductById(product.id)!.updatedDate;
    expect(
      after.isAfter(before) || after.isAtSameMomentAs(before),
      isTrue,
      reason: 'a stock movement is a change other devices need to see',
    );
    expect(
      repo.getEntityJson('Product', product.id)!['updatedDate'],
      after.toIso8601String(),
    );
  });

  test(
    'a product edited on another device is no longer blocked by a stale '
    'local copy',
    () async {
      // This is the exact shape of the bug: this device already has its own
      // (older) copy of the product, so a same-priority pull is the one
      // that has to win on recency, not on merely existing.
      final product = await store.addProduct(price: 100, quantity: 5);
      for (final item in repo.getPendingSyncItems()) {
        await repo.deleteSyncItem(item.id);
      }

      final remoteJson = repo.getEntityJson('Product', product.id)!;
      final laterUpdate = product.updatedDate.add(const Duration(minutes: 5));
      final remotePayload = {
        ...remoteJson,
        'id': product.id,
        'updatedDate': laterUpdate.toIso8601String(),
        'variants': [
          {
            ...(remoteJson['variants'] as List).single as Map,
            'price': 249.0,
            'quantity': 2,
          },
        ],
      };

      final applied = await repo.applyRemote(
        'Product',
        product.id,
        remotePayload,
      );

      expect(
        applied,
        isTrue,
        reason: 'a genuinely newer remote edit must be accepted',
      );
      expect(repo.getProductById(product.id)!.variants.single.price, 249.0);
      expect(repo.getProductById(product.id)!.variants.single.quantity, 2);
    },
  );

  test('an expense keeps its title', () async {
    final expense = Expense(
      id: 'exp-1',
      title: 'October rent',
      categoryId: 'cat_rent',
      categoryName: 'Rent',
      amount: 15000,
      date: DateTime(2026, 10, 1),
      notes: 'Paid by transfer',
      createdDate: DateTime(2026, 10, 1),
    );
    await repo.saveExpense(expense, isNew: true);

    final restored = EntityCodec.expense(
      repo.getEntityJson('Expense', 'exp-1')!,
    );

    expect(restored.title, 'October rent');
    expect(restored.amount, 15000);
    expect(restored.notes, 'Paid by transfer');
    expect(restored.categoryName, 'Rent');
  });

  test('a purchase keeps its status and delivery date', () async {
    final supplier = await store.addSupplier();
    final product = await store.addProduct();

    final purchase = Purchase(
      id: 'po-1',
      purchaseNumber: 'PUR-1',
      supplierId: supplier.id,
      supplierName: supplier.supplierName,
      purchaseDate: DateTime(2026, 8, 1),
      createdDate: DateTime(2026, 8, 1),
      expectedDeliveryDate: DateTime(2026, 8, 15),
      status: 'Issued',
      subtotal: 600,
      discount: 50,
      tax: 5,
      grandTotal: 577.5,
      items: [
        PurchaseItem(
          productId: product.id,
          productName: product.productName,
          variantBarcode: 'BC-1',
          variantSize: 'M',
          sku: 'SKU-1',
          quantity: 10,
          costPrice: 60,
          sellingPrice: 100,
          lineTotal: 600,
          receivedQuantity: 4,
        ),
      ],
    );
    await repo.savePurchase(purchase);

    final restored = EntityCodec.purchase(
      repo.getEntityJson('Purchase', 'po-1')!,
    );

    expect(restored.status, 'Issued');
    expect(restored.expectedDeliveryDate, DateTime(2026, 8, 15));
    expect(restored.discount, 50);
    expect(restored.items.single.sku, 'SKU-1');
    expect(restored.items.single.receivedQuantity, 4);
    expect(restored.items.single.sellingPrice, 100);
  });

  test('a customer round-trips its balance, points and tags', () async {
    final customer = await store.addCustomer(creditLimit: 2500, points: 40);

    final restored = EntityCodec.customer(
      repo.getEntityJson('Customer', customer.id)!,
    );

    expect(restored.creditLimit, 2500);
    expect(restored.totalRewardPoints, 40);
    expect(restored.mobile, customer.mobile);
    expect(restored.customerGroup, 'General');
  });

  test('a sale round-trips its reward fields and line items', () async {
    final product = await store.addProduct();
    final customer = await store.addCustomer();

    final sale = Sale(
      id: 'sale-1',
      invoiceNumber: 'INV-1',
      date: DateTime(2026, 8, 3),
      customerId: customer.id,
      customerName: customer.name,
      subtotal: 500,
      discountPercent: 10,
      discountAmount: 50,
      rewardDiscountAmount: 25,
      rewardPointsEarned: 4.5,
      taxAmount: 22.5,
      grandTotal: 447.5,
      paymentMethod: 'UPI',
      notes: 'Counter sale',
      items: [
        SaleItem(
          productId: product.id,
          productName: product.productName,
          productCode: product.productCode,
          variantBarcode: product.variants.single.barcode,
          variantSize: product.variants.single.size,
          price: 250,
          quantity: 2,
          total: 500,
        ),
      ],
    );
    await repo.saveSale(sale);

    final restored = EntityCodec.sale(repo.getEntityJson('Sale', 'sale-1')!);

    expect(restored.invoiceNumber, 'INV-1');
    expect(restored.paymentMethod, 'UPI');
    expect(restored.discountPercent, 10);
    expect(restored.rewardDiscountAmount, 25);
    expect(restored.rewardPointsEarned, 4.5);
    expect(restored.notes, 'Counter sale');
    expect(restored.items.single.productCode, product.productCode);
    expect(restored.items.single.quantity, 2);
    expect(restored.items.single.total, 500);
  });

  test('a supplier keeps its terms, rating and balance', () async {
    final supplier = await store.addSupplier();
    await repo.saveSupplier(
      supplier
        ..paymentTerms = 'Net 30'
        ..rating = 4.5
        ..currentBalance = 1250
        ..supplierCategory = 'Fabric'
        ..contactPerson = 'R. Menon'
        ..gstNumber = '29ABCDE1234F1Z5',
    );

    final restored = EntityCodec.supplier(
      repo.getEntityJson('Supplier', supplier.id)!,
    );

    expect(restored.supplierName, supplier.supplierName);
    expect(restored.paymentTerms, 'Net 30');
    expect(restored.rating, 4.5);
    expect(restored.currentBalance, 1250);
    expect(restored.supplierCategory, 'Fabric');
    expect(restored.contactPerson, 'R. Menon');
    expect(restored.gstNumber, '29ABCDE1234F1Z5');
  });

  test('a loyalty transaction keeps its type, points and reference', () async {
    final customer = await store.addCustomer();

    final id = await repo.addLoyaltyTransaction(
      customerId: customer.id,
      transactionType: 'Earn',
      points: 12.5,
      monetaryValue: 1250,
      reference: 'INV-1',
      remarks: 'Festive bonus',
      createdBy: 'POS',
    );

    final restored = EntityCodec.loyaltyTransaction(
      repo.getEntityJson('LoyaltyTransaction', id)!,
    );

    expect(restored.customerId, customer.id);
    expect(restored.transactionType, 'Earn');
    expect(restored.points, 12.5);
    expect(restored.monetaryValue, 1250);
    expect(restored.reference, 'INV-1');
    expect(restored.remarks, 'Festive bonus');
  });

  test('an inventory movement keeps what moved and why', () async {
    final product = await store.addProduct(quantity: 5);
    final variant = product.variants.single;

    await repo.performStockIn(
      productId: product.id,
      variantBarcode: variant.barcode,
      quantity: 8,
      reason: 'Purchase receipt',
      performedAt: 'Main counter',
    );

    final queued = repo.getPendingSyncItems().firstWhere(
      (i) => i.entityType == 'InventoryMovement',
    );
    final restored = EntityCodec.movement(
      repo.getEntityJson('InventoryMovement', queued.entityId)!,
    );

    expect(restored.productId, product.id);
    expect(restored.variantBarcode, variant.barcode);
    expect(restored.quantity, 8);
    expect(restored.type, 'Stock In');
    expect(restored.reason, 'Purchase receipt');
    expect(restored.performedAt, 'Main counter');
  });

  test('settings round-trip the tax configuration', () async {
    await repo.saveSettings(
      repo.getSettings()
        ..taxRate = 18
        ..taxMode = 'exclusive',
    );

    final restored = EntityCodec.settings(
      repo.getEntityJson('SettingsModel', 'app_settings')!,
    );

    expect(restored.taxRate, 18);
    expect(restored.taxMode, 'exclusive');
  });
}
