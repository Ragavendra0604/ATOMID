import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/domain/gst/gst_treatment.dart';
import 'package:atomid/domain/services/purchase_service.dart';

import '../support/test_store.dart';

/// Purchase GST, now computed by the same engine as a sale.
///
/// Every expected figure here is written out by hand rather than taken from
/// the engine, so a change in the engine shows up as a failure instead of
/// silently moving the target.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late PurchaseService service;

  Future<void> configureShop({
    String state = 'Tamil Nadu',
    String stateCode = '33',
    String gstin = '33AAAAA0000A1Z5',
  }) async {
    await store.repository.saveCompany(
      CompanyModel(
        name: 'Atomid Store',
        gstNumber: gstin,
        state: state,
        stateCode: stateCode,
      ),
    );
  }

  Future<Supplier> addSupplier({
    String gstin = '',
    String state = '',
    String stateCode = '',
  }) async {
    final supplier = Supplier(
      id: 'sup-1',
      supplierCode: 'SUP-1',
      supplierName: 'Weaving Mills',
      phone: '9000000000',
      gstNumber: gstin,
      state: state,
      stateCode: stateCode,
      createdDate: DateTime(2026, 1, 1),
      updatedDate: DateTime(2026, 1, 1),
    );
    await store.repository.saveSupplier(supplier);
    return supplier;
  }

  PurchaseItem itemOf({
    double costPrice = 100,
    int quantity = 10,
    double? gstRate = 5.0,
    String treatment = GstTreatment.taxable,
    double cessRate = 0.0,
    double discount = 0.0,
    String id = 'p1',
  }) => PurchaseItem(
    productId: id,
    productName: 'Cotton Bale',
    variantBarcode: 'B-$id',
    variantSize: 'M',
    quantity: quantity,
    costPrice: costPrice,
    sellingPrice: costPrice * 2,
    lineTotal: costPrice * quantity,
    hsn: '5208',
    uqc: 'PCS',
    gstRate: gstRate,
    gstTreatment: treatment,
    cessRate: cessRate,
    discountAmount: discount,
  );

  Purchase orderOf({
    required Supplier supplier,
    List<PurchaseItem>? items,
    String pricingMode = 'exclusive',
    DateTime? date,
  }) => Purchase(
    id: 'pur-1',
    purchaseNumber: 'PUR-0001',
    supplierId: supplier.id,
    supplierName: supplier.supplierName,
    purchaseDate: date ?? DateTime(2026, 1, 15),
    createdDate: DateTime(2026, 1, 15),
    subtotal: 0,
    discount: 0,
    tax: 0,
    grandTotal: 0,
    status: PurchaseStatus.draft,
    pricingMode: pricingMode,
    items: items ?? [itemOf()],
  );

  setUp(() async {
    store = await TestStore.open();
    service = PurchaseService(store.repository);
  });
  tearDown(() => store.close());

  group('rate and treatment must be configured', () {
    test('a null rate blocks instead of becoming 0%', () async {
      await configureShop();
      final supplier = await addSupplier(stateCode: '33', state: 'Tamil Nadu');
      final order = orderOf(supplier: supplier, items: [itemOf(gstRate: null)]);

      expect(
        () => service.computePurchaseGst(order),
        throwsA(
          isA<AppException>().having(
            (e) => e.toString(),
            'message',
            contains('no GST rate configured'),
          ),
        ),
      );
    });

    test('an unconfigured treatment blocks', () async {
      await configureShop();
      final supplier = await addSupplier(stateCode: '33', state: 'Tamil Nadu');
      final order = orderOf(
        supplier: supplier,
        items: [itemOf(gstRate: null, treatment: GstTreatment.unconfigured)],
      );

      expect(
        () => service.computePurchaseGst(order),
        throwsA(isA<AppException>()),
      );
    });

    test('an explicit 0% stays 0% and does not block', () async {
      await configureShop();
      final supplier = await addSupplier(stateCode: '33', state: 'Tamil Nadu');
      final order = orderOf(supplier: supplier, items: [itemOf(gstRate: 0)]);

      service.computePurchaseGst(order);

      expect(order.taxableAmount, 1000.0);
      expect(order.tax, 0.0);
      expect(order.grandTotal, 1000.0);
      expect(order.items.first.gstRate, 0.0);
    });

    test('an explicit 5% stays 5%', () async {
      await configureShop();
      final supplier = await addSupplier(stateCode: '33', state: 'Tamil Nadu');
      final order = orderOf(supplier: supplier);

      service.computePurchaseGst(order);

      expect(order.items.first.gstRate, 5.0);
      expect(order.taxableAmount, 1000.0);
      expect(order.cgstAmount, 25.0);
      expect(order.sgstAmount, 25.0);
      expect(order.grandTotal, 1050.0);
    });

    test('nil-rated and exempt lines carry no tax', () async {
      await configureShop();
      final supplier = await addSupplier(stateCode: '33', state: 'Tamil Nadu');
      for (final treatment in [
        GstTreatment.nilRated,
        GstTreatment.exempt,
        GstTreatment.nonGst,
      ]) {
        final order = orderOf(
          supplier: supplier,
          items: [itemOf(gstRate: 18, treatment: treatment)],
        );
        service.computePurchaseGst(order);
        expect(order.tax, 0.0, reason: treatment);
        expect(order.grandTotal, 1000.0, reason: treatment);
      }
    });

    test('a rate not yet effective on the purchase date blocks', () async {
      await configureShop();
      final supplier = await addSupplier(stateCode: '33', state: 'Tamil Nadu');
      // Before 01-Jul-2017, so no entry in the rate book covers it.
      final order = orderOf(supplier: supplier, date: DateTime(2016, 1, 1));

      expect(
        () => service.computePurchaseGst(order),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('place of supply', () {
    test('a same-state supplier gives CGST + SGST', () async {
      await configureShop();
      final supplier = await addSupplier(stateCode: '33', state: 'Tamil Nadu');
      final order = orderOf(supplier: supplier);

      service.computePurchaseGst(order);

      expect(order.isInterState, false);
      expect(order.cgstAmount, 25.0);
      expect(order.sgstAmount, 25.0);
      expect(order.utgstAmount, 0.0);
      expect(order.igstAmount, 0.0);
    });

    test('a union territory without legislature gives CGST + UTGST', () async {
      await configureShop(
        state: 'Chandigarh',
        stateCode: '04',
        gstin: '04AAAAA0000A1Z5',
      );
      final supplier = await addSupplier(stateCode: '04', state: 'Chandigarh');
      final order = orderOf(supplier: supplier);

      service.computePurchaseGst(order);

      expect(order.isInterState, false);
      expect(order.cgstAmount, 25.0);
      expect(order.utgstAmount, 25.0);
      expect(order.sgstAmount, 0.0);
    });

    test('a different-state supplier gives IGST', () async {
      await configureShop();
      final supplier = await addSupplier(stateCode: '27', state: 'Maharashtra');
      final order = orderOf(supplier: supplier);

      service.computePurchaseGst(order);

      expect(order.isInterState, true);
      expect(order.igstAmount, 50.0);
      expect(order.cgstAmount, 0.0);
      expect(order.sgstAmount, 0.0);
    });

    test(
      'a valid supplier GSTIN supplies the state when none is set',
      () async {
        await configureShop();
        // The Mumbai case: nothing but a GSTIN on the record.
        final supplier = await addSupplier(gstin: '27ABCDE1234F1Z5');
        final order = orderOf(supplier: supplier);

        service.computePurchaseGst(order);

        expect(order.supplierStateCode, '27');
        expect(order.supplierState, 'Maharashtra');
        expect(order.isInterState, true);
        expect(order.igstAmount, 50.0);
        expect(order.cgstAmount, 0.0);
      },
    );

    test('a GSTIN agreeing with the recorded state is accepted', () async {
      await configureShop();
      final supplier = await addSupplier(
        gstin: '27ABCDE1234F1Z5',
        stateCode: '27',
        state: 'Maharashtra',
      );
      final order = orderOf(supplier: supplier);

      service.computePurchaseGst(order);

      expect(order.supplierStateCode, '27');
      expect(order.igstAmount, 50.0);
    });

    test('a GSTIN disagreeing with the recorded state blocks', () async {
      await configureShop();
      final supplier = await addSupplier(
        gstin: '27ABCDE1234F1Z5',
        stateCode: '29',
        state: 'Karnataka',
      );
      final order = orderOf(supplier: supplier);

      expect(
        () => service.computePurchaseGst(order),
        throwsA(
          isA<AppException>().having(
            (e) => e.toString(),
            'message',
            contains('do not agree'),
          ),
        ),
      );
    });

    test('an invalid GSTIN yields no state and blocks', () async {
      await configureShop();
      final supplier = await addSupplier(gstin: 'NOTAGSTIN123');
      final order = orderOf(supplier: supplier);

      expect(
        () => service.computePurchaseGst(order),
        throwsA(isA<AppException>()),
      );
    });

    test('an unconfigured shop blocks — no Tamil Nadu fallback', () async {
      // Deliberately no saveCompany.
      final supplier = await addSupplier(stateCode: '27', state: 'Maharashtra');
      final order = orderOf(supplier: supplier);

      expect(
        () => service.computePurchaseGst(order),
        throwsA(
          isA<AppException>().having(
            (e) => e.toString(),
            'message',
            contains('Shop state'),
          ),
        ),
      );
    });

    test(
      'an unknown supplier state is never guessed as the shop state',
      () async {
        await configureShop();
        final supplier = await addSupplier();

        expect(
          () => service.computePurchaseGst(orderOf(supplier: supplier)),
          throwsA(
            isA<AppException>().having(
              (e) => e.toString(),
              'message',
              contains('Supplier state is not set'),
            ),
          ),
        );
      },
    );
  });

  group('pricing', () {
    late Supplier supplier;
    setUp(() async {
      await configureShop();
      supplier = await addSupplier(stateCode: '33', state: 'Tamil Nadu');
    });

    test('exclusive adds tax on top of the cost price', () async {
      final order = orderOf(supplier: supplier);
      service.computePurchaseGst(order);

      expect(order.subtotal, 1000.0);
      expect(order.taxableAmount, 1000.0);
      expect(order.grandTotal, 1050.0);
      expect(order.pricingMode, 'exclusive');
    });

    test('inclusive extracts tax out of the cost price', () async {
      final order = orderOf(
        supplier: supplier,
        pricingMode: 'inclusive',
        items: [itemOf(costPrice: 105)],
      );
      service.computePurchaseGst(order);

      expect(order.subtotal, 1050.0);
      expect(order.taxableAmount, 1000.0);
      expect(order.cgstAmount, 25.0);
      expect(order.sgstAmount, 25.0);
      expect(order.grandTotal, 1050.0);
    });

    test('a line discount reduces that line only', () async {
      final order = orderOf(supplier: supplier, items: [itemOf(discount: 100)]);
      service.computePurchaseGst(order);

      expect(order.subtotal, 1000.0);
      expect(order.items.first.discountAmount, 100.0);
      expect(order.taxableAmount, 900.0);
      expect(order.cgstAmount, 22.50);
      expect(order.sgstAmount, 22.50);
      expect(order.grandTotal, 945.0);
    });

    test('mixed rates are summed per head', () async {
      final order = orderOf(
        supplier: supplier,
        items: [
          itemOf(gstRate: 5),
          itemOf(id: 'p2', costPrice: 200, gstRate: 12),
        ],
      );
      service.computePurchaseGst(order);

      // 1000 @ 5% = 50, 2000 @ 12% = 240.
      expect(order.taxableAmount, 3000.0);
      expect(order.cgstAmount, 145.0);
      expect(order.sgstAmount, 145.0);
      expect(order.grandTotal, 3290.0);
    });

    test('cess is charged alongside GST', () async {
      final order = orderOf(
        supplier: supplier,
        items: [itemOf(gstRate: 28, cessRate: 12)],
      );
      service.computePurchaseGst(order);

      expect(order.cgstAmount, 140.0);
      expect(order.sgstAmount, 140.0);
      expect(order.cessAmount, 120.0);
      expect(order.tax, 400.0);
      expect(order.grandTotal, 1400.0);
    });

    test('round-off is applied and recorded', () async {
      final order = orderOf(
        supplier: supplier,
        items: [itemOf(costPrice: 99.50, quantity: 1)],
      );
      service.computePurchaseGst(order);

      expect(order.preRoundTotal, 104.48);
      expect(order.roundOff, -0.48);
      expect(order.grandTotal, 104.0);
    });
  });

  group('snapshot', () {
    test('a finalized purchase does not move when the world changes', () async {
      await configureShop();
      final supplier = await addSupplier(
        gstin: '27ABCDE1234F1Z5',
        stateCode: '27',
        state: 'Maharashtra',
      );

      final product = await store.addProduct(quantity: 5, gstRate: 5);
      final order = orderOf(
        supplier: supplier,
        items: [itemOf(id: product.id, gstRate: 5)],
      );
      await service.savePurchase(order, isNew: true);

      final frozen = {
        'taxable': order.taxableAmount,
        'igst': order.igstAmount,
        'cgst': order.cgstAmount,
        'grand': order.grandTotal,
        'preRound': order.preRoundTotal,
        'roundOff': order.roundOff,
        'supplierState': order.supplierState,
        'supplierStateCode': order.supplierStateCode,
        'supplierGstin': order.supplierGstin,
        'recipientName': order.recipientName,
        'recipientGstin': order.recipientGstin,
        'recipientState': order.recipientState,
        'recipientStateCode': order.recipientStateCode,
        'pricingMode': order.pricingMode,
        'lineRate': order.items.first.gstRate,
        'lineTaxable': order.items.first.taxableValue,
        'lineHsn': order.items.first.hsn,
      };

      expect(frozen['recipientState'], 'Tamil Nadu');
      expect(frozen['supplierState'], 'Maharashtra');

      // Everything the figures were derived from now changes.
      await configureShop(
        state: 'Karnataka',
        stateCode: '29',
        gstin: '29AAAAA0000A1Z5',
      );
      final movedSupplier = store.repository.getSupplierById(supplier.id)!;
      movedSupplier.state = 'Kerala';
      movedSupplier.stateCode = '32';
      movedSupplier.gstNumber = '32AABCK9999P1Z1';
      await store.repository.saveSupplier(movedSupplier);

      final movedProduct = store.repository.getProductById(product.id)!;
      movedProduct.gstRate = 28.0;
      movedProduct.hsn = '9999';
      await store.repository.saveProduct(movedProduct);

      await store.repository.saveSettings(
        SettingsModel(taxRate: 18, roundOffEnabled: false),
      );

      final reread = store.repository.getPurchaseById(order.id)!;
      expect(reread.taxableAmount, frozen['taxable']);
      expect(reread.igstAmount, frozen['igst']);
      expect(reread.cgstAmount, frozen['cgst']);
      expect(reread.grandTotal, frozen['grand']);
      expect(reread.preRoundTotal, frozen['preRound']);
      expect(reread.roundOff, frozen['roundOff']);
      expect(reread.supplierState, frozen['supplierState']);
      expect(reread.supplierStateCode, frozen['supplierStateCode']);
      expect(reread.supplierGstin, frozen['supplierGstin']);
      expect(reread.recipientName, frozen['recipientName']);
      expect(reread.recipientGstin, frozen['recipientGstin']);
      expect(reread.recipientState, frozen['recipientState']);
      expect(reread.recipientStateCode, frozen['recipientStateCode']);
      expect(reread.pricingMode, frozen['pricingMode']);
      expect(reread.items.first.gstRate, frozen['lineRate']);
      expect(reread.items.first.taxableValue, frozen['lineTaxable']);
      expect(reread.items.first.hsn, frozen['lineHsn']);
    });
  });

  group('input tax credit', () {
    test('defaults to REQUIRES_DETERMINATION and is never claimed', () async {
      await configureShop();
      final supplier = await addSupplier(stateCode: '33', state: 'Tamil Nadu');
      final order = orderOf(supplier: supplier);

      await service.savePurchase(order, isNew: true);

      expect(order.itcEligibility, 'REQUIRES_DETERMINATION');
      expect(
        store.repository.getPurchaseById(order.id)!.itcEligibility,
        'REQUIRES_DETERMINATION',
      );
    });
  });
}
