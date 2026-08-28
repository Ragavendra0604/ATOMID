import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/domain/gst/gst_states.dart';
import 'package:atomid/domain/gst/gst_treatment.dart';
import 'package:atomid/domain/services/purchase_service.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

class PurchaseFormScreen extends ConsumerStatefulWidget {
  final Purchase? existingPurchase;

  const PurchaseFormScreen({super.key, this.existingPurchase});

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  Supplier? _selectedSupplier;
  final _notesCtrl = TextEditingController();
  final _supplierInvoiceNumberCtrl = TextEditingController();
  final _supplierGstinCtrl = TextEditingController();
  // Unset, not Tamil Nadu. A pre-filled state is a stated state as far as the
  // engine is concerned, so defaulting it here would put back the guess that
  // was just taken out of the calculation.
  String _supplierStateCode = '';
  DateTime? _supplierInvoiceDate = DateTime.now();

  bool _isProcessing = false;
  String _status = PurchaseStatus.draft;
  String? _originalStatus;
  DateTime? _expectedDeliveryDate;

  final List<_LineItem> _lineItems = [];

  bool get _isEditing => widget.existingPurchase != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingPurchase;
    if (existing == null) {
      final shop = ref.read(companyProvider);
      // Most purchases are local, so the shop's own state is a sensible
      // starting point — but only once the shop actually has one.
      _supplierStateCode = shop.stateCode;
      return;
    }

    _originalStatus = existing.status;
    _status = existing.status;
    _notesCtrl.text = existing.notes;
    _supplierInvoiceNumberCtrl.text = existing.supplierInvoiceNumber;
    _supplierInvoiceDate =
        existing.supplierInvoiceDate ?? existing.purchaseDate;
    _supplierGstinCtrl.text = existing.supplierGstin;
    _supplierStateCode = existing.supplierStateCode;
    _expectedDeliveryDate = existing.expectedDeliveryDate;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final repo = ref.read(storageRepositoryProvider);
      _selectedSupplier = repo.getSupplierById(existing.supplierId);

      for (final item in existing.items) {
        final product = repo.getProductById(item.productId);
        final line = _LineItem()
          ..selectedProduct = product
          ..selectedVariant = product?.variants
              .cast<ProductVariant?>()
              .firstWhere(
                (v) => v?.barcode == item.variantBarcode,
                orElse: () => null,
              )
          ..hsnCtrl.text = item.hsn
          ..uqc = item.uqc
          ..gstTreatment = item.gstTreatment
          ..gstRate = item.gstRate ?? (product?.gstRate ?? 5.0)
          ..cessCtrl.text = Fmt.amount(item.cessRate)
          ..discountCtrl.text = Fmt.amount(item.discountAmount)
          ..qtyCtrl.text = item.quantity.toString()
          ..costPriceCtrl.text = Fmt.amount(item.costPrice);
        _lineItems.add(line);
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _supplierInvoiceNumberCtrl.dispose();
    _supplierGstinCtrl.dispose();
    for (var item in _lineItems) {
      item.dispose();
    }
    super.dispose();
  }

  void _addLineItem() {
    setState(() {
      final line = _LineItem();
      _lineItems.add(line);
    });
  }

  void _removeLineItem(int index) {
    setState(() {
      _lineItems[index].dispose();
      _lineItems.removeAt(index);
    });
  }

  /// Why the running preview could not be taxed, if it could not be.
  String? _gstIssue;

  Purchase _buildTransientPurchase() {
    final company = ref.read(companyProvider);
    final isInterState = _supplierStateCode != company.stateCode;
    final supplierStateName =
        GstStates.findByCode(_supplierStateCode)?.name ?? company.state;

    final items = <PurchaseItem>[];
    for (final line in _lineItems) {
      if (line.selectedProduct == null || line.selectedVariant == null) {
        continue;
      }
      items.add(
        PurchaseItem(
          productId: line.selectedProduct!.id,
          productName: line.selectedProduct!.productName,
          variantBarcode: line.selectedVariant!.barcode,
          variantSize: line.selectedVariant!.size,
          sku: line.selectedVariant!.sku,
          quantity: line.qty,
          costPrice: line.costPrice,
          sellingPrice: line.selectedVariant!.price,
          lineTotal: 0.0,
          hsn: line.hsnCtrl.text.trim().isNotEmpty
              ? line.hsnCtrl.text.trim()
              : line.selectedProduct!.hsn,
          uqc: line.uqc,
          gstRate: line.gstRate,
          gstTreatment: line.gstTreatment,
          cessRate: double.tryParse(line.cessCtrl.text) ?? 0.0,
          discountAmount: line.discount,
        ),
      );
    }

    final p = Purchase(
      id: widget.existingPurchase?.id ?? Ids.generate(),
      purchaseNumber: widget.existingPurchase?.purchaseNumber ?? '',
      purchaseDate: _supplierInvoiceDate ?? DateTime.now(),
      supplierId: _selectedSupplier?.id ?? '',
      supplierName: _selectedSupplier?.supplierName ?? '',
      supplierInvoiceNumber: _supplierInvoiceNumberCtrl.text.trim(),
      supplierInvoiceDate: _supplierInvoiceDate,
      supplierGstin: _supplierGstinCtrl.text.trim().toUpperCase(),
      supplierState: supplierStateName,
      supplierStateCode: _supplierStateCode,
      itcEligibility: 'REQUIRES_DETERMINATION',
      subtotal: 0.0,
      discount: 0.0,
      tax: 0.0,
      grandTotal: 0.0,
      status: _status,
      notes: _notesCtrl.text.trim(),
      expectedDeliveryDate: _expectedDeliveryDate,
      createdDate: widget.existingPurchase?.createdDate ?? DateTime.now(),
      items: items,
      isInterState: isInterState,
    );

    // The non-throwing variant: this runs inside `build`, where an exception
    // is an error screen rather than a message. The save path still refuses.
    _gstIssue = ref.read(purchaseServiceProvider).tryComputePurchaseGst(p);
    return p;
  }

  Future<void> _savePurchase() async {
    if (_isProcessing) return;

    if (_selectedSupplier == null) {
      _showError('Please select a supplier.');
      return;
    }

    if (_lineItems.isEmpty) {
      _showError('Please add at least one line item.');
      return;
    }

    for (var i = 0; i < _lineItems.length; i++) {
      final item = _lineItems[i];
      if (item.selectedProduct == null || item.selectedVariant == null) {
        _showError('Please complete product selection for line item #${i + 1}');
        return;
      }
      if (item.qty <= 0) {
        _showError('Quantity must be greater than 0 for line item #${i + 1}');
        return;
      }
      if (item.costPrice < 0) {
        _showError('Cost price cannot be negative for line item #${i + 1}');
        return;
      }
    }

    setState(() => _isProcessing = true);

    try {
      final purchase = _buildTransientPurchase();
      if (purchase.purchaseNumber.isEmpty) {
        purchase.purchaseNumber = ref
            .read(storageRepositoryProvider)
            .getNextPurchaseNumber();
      }

      await ref
          .read(purchaseServiceProvider)
          .savePurchase(
            purchase,
            isNew: widget.existingPurchase == null,
            previousStatus: _originalStatus,
          );

      if (mounted) {
        final received =
            _status == PurchaseStatus.received &&
            _originalStatus != PurchaseStatus.received;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              received
                  ? 'Purchase ${purchase.purchaseNumber} received — stock and GST updated.'
                  : 'Purchase ${purchase.purchaseNumber} saved as ${_status.toLowerCase()}.',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e, stack) {
      debugPrint('Purchase form error: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              describeError(
                e,
                fallback: 'The purchase could not be saved. Please try again.',
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final activeSuppliers = ref.watch(activeSuppliersProvider);
    final products = ref.watch(productsProvider);
    final settings = ref.watch(settingsProvider);
    final transientPurchase = _buildTransientPurchase();

    final gstIssue = _gstIssue;
    final gstin = _supplierGstinCtrl.text.trim();
    final isGstinValid = gstin.isNotEmpty && GstStates.isValidGstin(gstin);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? 'Edit ${widget.existingPurchase!.purchaseNumber}'
              : 'Record Inward Purchase',
        ),
        actions: [
          if (_isProcessing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save Purchase',
              onPressed: _savePurchase,
            ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final supplierCard = Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Supplier & Invoice Information',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Supplier>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Select Supplier *',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: _selectedSupplier,
                    items: activeSuppliers.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(
                          s.supplierName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedSupplier = val;
                        if (val != null) {
                          if (val.gstNumber.isNotEmpty) {
                            _supplierGstinCtrl.text = val.gstNumber;
                          }
                          if (val.stateCode.isNotEmpty) {
                            _supplierStateCode = val.stateCode;
                          }
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _supplierInvoiceNumberCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Supplier Invoice Number',
                            border: OutlineInputBorder(),
                            helperText: 'e.g. INV-84920',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  _supplierInvoiceDate ?? DateTime.now(),
                              firstDate: DateTime(2017, 7, 1),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              setState(() => _supplierInvoiceDate = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Supplier Invoice Date',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              _supplierInvoiceDate == null
                                  ? 'Pick date'
                                  : Fmt.date(_supplierInvoiceDate!),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _supplierGstinCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Supplier GSTIN',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _supplierStateCode,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Supplier State',
                            border: OutlineInputBorder(),
                            helperText: 'A valid supplier GSTIN supplies this',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Not set'),
                            ),
                            ...GstStates.allStates.map(
                              (s) => DropdownMenuItem(
                                value: s.code,
                                child: Text(
                                  '${s.name} (${s.code})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (val) =>
                              setState(() => _supplierStateCode = val ?? ''),
                        ),
                      ),
                    ],
                  ),
                  if (gstin.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Row(
                        children: [
                          Icon(
                            isGstinValid
                                ? Icons.check_circle
                                : Icons.error_outline,
                            size: 16,
                            color: isGstinValid ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isGstinValid
                                ? 'Supplier GSTIN format valid'
                                : 'GSTIN format incomplete',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isGstinValid
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Order Lifecycle Status',
                            border: OutlineInputBorder(),
                          ),
                          initialValue: _status,
                          items:
                              const [
                                PurchaseStatus.draft,
                                PurchaseStatus.issued,
                                PurchaseStatus.received,
                              ].map((s) {
                                return DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _status = val);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );

          final itcBanner = Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border.all(color: Colors.blue.shade200),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: Colors.blue.shade800,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Input Tax Credit (ITC) Determination: REQUIRES_DETERMINATION\n'
                    'Statutory claim status recorded for purchase tax filing.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );

          final lineItemsSection = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Inward Purchase Items',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _addLineItem,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Dress / Item'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_lineItems.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No items added yet. Click "Add Dress / Item".',
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                ..._lineItems.asMap().entries.map((entry) {
                  return _buildLineItemCard(
                    entry.key,
                    entry.value,
                    products,
                    settings.currencySymbol,
                  );
                }),
            ],
          );

          final summaryCard = Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Purchase Tax & Total Summary',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Shown instead of a total that cannot be trusted. Saving is
                  // refused for the same reason, with the same wording.
                  if (gstIssue != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.errorContainer.withAlpha(120),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              gstIssue,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  _summaryRow(
                    'Subtotal (Gross)',
                    Fmt.money(
                      transientPurchase.subtotal,
                      settings.currencySymbol,
                    ),
                  ),
                  _summaryRow(
                    'Taxable Value',
                    Fmt.money(
                      transientPurchase.taxableAmount,
                      settings.currencySymbol,
                    ),
                  ),
                  if (transientPurchase.isInterState) ...[
                    _summaryRow(
                      'Integrated GST (IGST)',
                      Fmt.money(
                        transientPurchase.igstAmount,
                        settings.currencySymbol,
                      ),
                    ),
                  ] else ...[
                    _summaryRow(
                      'Central GST (CGST)',
                      Fmt.money(
                        transientPurchase.cgstAmount,
                        settings.currencySymbol,
                      ),
                    ),
                    _summaryRow(
                      'State/UT GST (SGST)',
                      Fmt.money(
                        transientPurchase.sgstAmount +
                            transientPurchase.utgstAmount,
                        settings.currencySymbol,
                      ),
                    ),
                  ],
                  if (transientPurchase.cessAmount > 0)
                    _summaryRow(
                      'Cess Amount',
                      Fmt.money(
                        transientPurchase.cessAmount,
                        settings.currencySymbol,
                      ),
                    ),
                  const Divider(height: 20),
                  _summaryRow(
                    'Grand Total',
                    Fmt.money(
                      transientPurchase.grandTotal,
                      settings.currencySymbol,
                    ),
                    isBold: true,
                    fontSize: 18,
                  ),
                ],
              ),
            ),
          );

          return SingleChildScrollView(
            padding: ResponsivePadding.getScreenPadding(context),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    itcBanner,
                    supplierCard,
                    const SizedBox(height: 16),
                    lineItemsSection,
                    const SizedBox(height: 16),
                    summaryCard,
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notes',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _notesCtrl,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                hintText: 'Optional purchase order notes…',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _savePurchase,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        'Save Purchase (${Fmt.money(transientPurchase.grandTotal, settings.currencySymbol)})',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool isBold = false,
    double fontSize = 14,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineItemCard(
    int index,
    _LineItem item,
    List<Product> products,
    String currencySymbol,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<Product>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Select Dress / Product *',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    initialValue: item.selectedProduct,
                    items: products.map((p) {
                      return DropdownMenuItem(
                        value: p,
                        child: Text(
                          p.productName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (p) {
                      setState(() {
                        item.selectedProduct = p;
                        item.selectedVariant = p?.variants.firstOrNull;
                        if (p != null) {
                          item.gstRate = p.gstRate ?? 5.0;
                          item.gstTreatment = p.gstTreatment;
                          item.hsnCtrl.text = p.hsn;
                          item.uqc = p.uqc;
                          if (item.selectedVariant != null) {
                            item.costPriceCtrl.text =
                                item.selectedVariant!.costPrice > 0
                                ? Fmt.amount(item.selectedVariant!.costPrice)
                                : Fmt.amount(item.selectedVariant!.price);
                          }
                        }
                      });
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Remove line item',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _removeLineItem(index),
                ),
              ],
            ),
            if (item.selectedProduct != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<ProductVariant>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Size Variant *',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      initialValue: item.selectedVariant,
                      items: item.selectedProduct!.variants.map((v) {
                        return DropdownMenuItem(
                          value: v,
                          child: Text('Size: ${v.size}'),
                        );
                      }).toList(),
                      onChanged: (v) {
                        setState(() {
                          item.selectedVariant = v;
                          if (v != null && v.costPrice > 0) {
                            item.costPriceCtrl.text = Fmt.amount(v.costPrice);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: item.qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Qty *',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: item.costPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Cost ($currencySymbol) *',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<double?>(
                      initialValue: item.gstRate,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'GST %',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0.0, child: Text('0%')),
                        DropdownMenuItem(value: 5.0, child: Text('5%')),
                        DropdownMenuItem(value: 12.0, child: Text('12%')),
                        DropdownMenuItem(value: 18.0, child: Text('18%')),
                        DropdownMenuItem(value: 28.0, child: Text('28%')),
                      ],
                      onChanged: (r) {
                        if (r != null) setState(() => item.gstRate = r);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: item.hsnCtrl,
                      decoration: const InputDecoration(
                        labelText: 'HSN Code',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: item.discountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Discount (₹)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineItem {
  Product? selectedProduct;
  ProductVariant? selectedVariant;
  final qtyCtrl = TextEditingController(text: '1');
  final costPriceCtrl = TextEditingController(text: '0');
  final discountCtrl = TextEditingController(text: '0');
  final hsnCtrl = TextEditingController();
  final cessCtrl = TextEditingController(text: '0');
  String gstTreatment = GstTreatment.taxable;
  double? gstRate = 5.0;
  String uqc = 'PCS';

  int get qty => int.tryParse(qtyCtrl.text) ?? 1;
  double get costPrice => double.tryParse(costPriceCtrl.text) ?? 0.0;
  double get discount => double.tryParse(discountCtrl.text) ?? 0.0;
  double get lineTotal => (qty * costPrice) - discount;

  void dispose() {
    qtyCtrl.dispose();
    costPriceCtrl.dispose();
    discountCtrl.dispose();
    hsnCtrl.dispose();
    cessCtrl.dispose();
  }
}
