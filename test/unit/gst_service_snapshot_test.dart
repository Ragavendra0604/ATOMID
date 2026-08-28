import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/domain/cart_item.dart';
import 'package:atomid/domain/gst/gst_treatment.dart';
import 'package:atomid/domain/pricing.dart';
import 'package:atomid/domain/services/purchase_service.dart';
import 'package:atomid/domain/services/sale_service.dart';
import 'package:atomid/domain/services/session_service.dart';

import '../support/test_store.dart';

class MockSessionService extends Mock implements SessionService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();

  late TestStore store;
  late SaleService saleService;
  late PurchaseService purchaseService;
  late MockSessionService session;

  setUp(() async {
    store = await TestStore.open();
    session = MockSessionService();
    when(() => session.deviceId).thenReturn('dev_test_abcd');

    final company = CompanyModel(
      name: 'Radha Silks & Readymades',
      tradeName: 'Radha Silks',
      gstNumber: '33AABCR1234F1Z5',
      state: 'Tamil Nadu',
      stateCode: '33',
      address: '77 South Car Street, Tirunelveli',
    );
    await store.repository.saveCompany(company);

    final settings = SettingsModel(
      taxMode: TaxMode.inclusive,
      currencySymbol: '₹',
      roundOffEnabled: true,
    );
    await store.repository.saveSettings(settings);

    saleService = SaleService(store.repository, session);
    purchaseService = PurchaseService(store.repository);
  });

  tearDown(() => store.close());

  test(
    'Sale checkout freezes immutable seller, customer, tax, and line snapshots',
    () async {
      final product = Product(
        id: 'prod-101',
        productName: 'Chanderi Salwar',
        productCode: 'CS-101',
        brand: 'Radha',
        color: 'Green',
        category: 'Salwars',
        hsn: '6204',
        uqc: 'PCS',
        gstTreatment: GstTreatment.taxable,
        gstRate: 5.0,
        createdDate: now,
        updatedDate: now,
        variants: [
          ProductVariant(
            size: 'L',
            price: 1050.0,
            costPrice: 600.0,
            quantity: 20,
            barcode: 'BAR-CS-101',
            sku: 'SKU-CS-101',
          ),
        ],
      );
      await store.repository.saveProduct(product);

      final customer = Customer(
        id: 'cust-b2b',
        name: 'Kerala Retail Hub',
        code: 'CUST-001',
        mobile: '9876543210',
        gstNumber: '32AABCK9999P1Z1',
        state: 'Kerala',
        stateCode: '32',
        createdDate: now,
      );
      await store.repository.saveCustomer(customer);

      final cartItem = CartItem(
        product: product,
        variant: product.variants.first,
        quantity: 2,
      );

      final req = CheckoutRequest(
        items: [cartItem],
        customer: customer,
        paymentMethod: 'UPI',
        discountPercent: 10.0,
      );

      final sale = await saleService.checkout(req);

      // Verify Sale Level Freeze
      expect(sale.documentType, 'Tax Invoice');
      expect(sale.sellerLegalName, 'Radha Silks & Readymades');
      expect(sale.sellerGstin, '33AABCR1234F1Z5');
      expect(sale.sellerState, 'Tamil Nadu');
      expect(sale.sellerStateCode, '33');
      expect(sale.customerName, 'Kerala Retail Hub');
      expect(sale.customerGstin, '32AABCK9999P1Z1');
      expect(sale.placeOfSupply, 'Kerala');
      expect(sale.isInterState, true);

      // Mathematical verification (Gross 2100 - 10% disc = 1890. Taxable @ 5% incl = 1800. IGST = 90)
      expect(sale.subtotal, 2100.0);
      expect(sale.discountAmount, 210.0);
      expect(sale.taxableAmount, 1800.0);
      expect(sale.cgstAmount, 0.0);
      expect(sale.sgstAmount, 0.0);
      expect(sale.igstAmount, 90.0);
      expect(sale.grandTotal, 1890.0);

      // Verify Line Level Freeze
      final line = sale.items.first;
      expect(line.hsn, '6204');
      expect(line.uqc, 'PCS');
      expect(line.gstRate, 5.0);
      expect(line.taxableValue, 1800.0);
      expect(line.igstAmount, 90.0);

      // Verify Inventory Decrement
      final updatedProduct = store.repository.getProductById(product.id)!;
      expect(updatedProduct.variants.first.quantity, 18);
    },
  );

  test(
    'Purchase inward computes supplier taxes and sets ITC determination status',
    () async {
      final supplier = Supplier(
        id: 'sup-mumbai',
        supplierCode: 'SUP-001',
        supplierName: 'Mumbai Wholesalers',
        contactPerson: 'Rajesh',
        phone: '9876543210',
        email: 'mumbai@wholesalers.com',
        address: 'Kalbadevi, Mumbai',
        gstNumber: '27AABCM8888K1Z3',
        state: 'Maharashtra',
        stateCode: '27',
        createdDate: now,
        updatedDate: now,
      );
      await store.repository.saveSupplier(supplier);

      final product = Product(
        id: 'prod-inward',
        productName: 'Georgette Anarkali',
        productCode: 'GA-200',
        brand: 'Radha',
        color: 'Maroon',
        category: 'Anarkalis',
        hsn: '6204',
        createdDate: now,
        updatedDate: now,
        variants: [
          ProductVariant(
            size: 'XL',
            price: 2000.0,
            costPrice: 1000.0,
            quantity: 5,
            barcode: 'BAR-GA-200',
            sku: 'SKU-GA-200',
          ),
        ],
      );
      await store.repository.saveProduct(product);

      final purchase = Purchase(
        id: 'pur-1',
        purchaseNumber: 'PUR-2026-0001',
        purchaseDate: now,
        supplierId: supplier.id,
        supplierName: supplier.supplierName,
        supplierInvoiceNumber: 'MW-INV-9921',
        supplierInvoiceDate: now,
        supplierGstin: supplier.gstNumber,
        supplierState: supplier.state,
        supplierStateCode: supplier.stateCode,
        itcEligibility: 'REQUIRES_DETERMINATION',
        subtotal: 0.0,
        discount: 0.0,
        tax: 0.0,
        grandTotal: 0.0,
        status: PurchaseStatus.received,
        notes: 'Initial stock lot',
        createdDate: now,
        items: [
          PurchaseItem(
            productId: product.id,
            productName: product.productName,
            variantBarcode: 'BAR-GA-200',
            variantSize: 'XL',
            sku: 'SKU-GA-200',
            quantity: 10,
            costPrice: 1000.0,
            sellingPrice: 2000.0,
            lineTotal: 0.0,
            hsn: '6204',
            uqc: 'PCS',
            gstRate: 5.0,
            gstTreatment: GstTreatment.taxable,
          ),
        ],
        isInterState: true,
      );

      await purchaseService.savePurchase(purchase, isNew: true);

      expect(purchase.itcEligibility, 'REQUIRES_DETERMINATION');
      expect(purchase.isInterState, true);
      expect(purchase.taxableAmount, 10000.0);
      expect(purchase.igstAmount, 500.0);
      expect(purchase.grandTotal, 10500.0);

      // Verify stock increment on received purchase
      final updatedProduct = store.repository.getProductById(product.id)!;
      expect(updatedProduct.variants.first.quantity, 15);
    },
  );
}
