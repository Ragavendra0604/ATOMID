import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/providers/cart_notifier.dart';
import 'package:atomid/presentation/providers/provider_refresh_helper.dart';
import 'package:atomid/presentation/features/billing/invoice_preview_screen.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/presentation/features/loyalty/widgets/customer_reward_card.dart';
import 'package:atomid/presentation/features/loyalty/widgets/reward_discount_widget.dart';
import 'package:atomid/presentation/features/customers/customer_form_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  final double subtotal;
  final double taxAmount;
  final double grandTotal;

  const CheckoutScreen({
    super.key,
    required this.subtotal,
    required this.taxAmount,
    required this.grandTotal,
  });

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _selectedPaymentMethod = 'Cash';
  final _notesController = TextEditingController();
  bool _isProcessing = false;
  Customer? _selectedCustomer;
  bool _isRedeemingPoints = false;
  double _manualDiscount = 0.0;

  final List<String> _paymentMethods = ['Cash', 'UPI', 'Card', 'Credit'];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _processCheckout() async {
    setState(() => _isProcessing = true);

    try {
      final repo = ref.read(storageRepositoryProvider);
      final cartItems = ref.read(cartProvider);

      // Double check stock validation
      final validationError = ref.read(cartProvider.notifier).validateStock();
      if (validationError != null) {
        throw Exception(validationError);
      }

      final invoiceNumber = repo.getNextInvoiceNumber();
      final now = DateTime.now();

      // Create Sale Items
      final List<SaleItem> saleItems = cartItems.map((item) {
        return SaleItem(
          productId: item.product.id,
          productName: item.product.productName,
          productCode: item.product.productCode,
          variantBarcode: item.variant.barcode,
          variantSize: item.variant.size,
          price: item.variant.price,
          quantity: item.quantity,
          total: item.total,
        );
      }).toList();

      // Create Sale Record
      final sale = Sale(
        id: now.millisecondsSinceEpoch.toString(),
        invoiceNumber: invoiceNumber,
        date: now,
        customerId: _selectedCustomer?.id ?? '',
        customerName: _selectedCustomer?.name ?? 'Walk-In Customer',
        items: saleItems,
        subtotal: widget.subtotal,
        discountPercent: 0,
        discountAmount: 0, // Base discount
        rewardDiscountAmount: 0, // To be updated below
        rewardPointsEarned: 0, // To be updated below
        taxAmount: widget.taxAmount,
        grandTotal: widget.grandTotal,
        paymentMethod: _selectedPaymentMethod,
        notes: _notesController.text.trim(),
      );

      double appliedRewardDiscount = 0;
      double finalGrandTotal = widget.grandTotal;

      if (_selectedCustomer != null) {
         final maxRedeemable = repo.calculateMaxRedemptionValue(_selectedCustomer!.totalRewardPoints, widget.subtotal);
         if (_isRedeemingPoints) {
            appliedRewardDiscount = maxRedeemable;
            finalGrandTotal -= appliedRewardDiscount;
         }
      }
      
      finalGrandTotal -= _manualDiscount;
      if (finalGrandTotal < 0) finalGrandTotal = 0;

      sale.discountAmount = _manualDiscount;
      sale.rewardDiscountAmount = appliedRewardDiscount;
      sale.grandTotal = finalGrandTotal;
      sale.rewardPointsEarned = repo.calculateEarnedPoints(finalGrandTotal);

      // Save Sale
      await repo.saveSale(sale);

      // Deduct stock for each item
      for (var item in cartItems) {
        await repo.performStockOut(
          productId: item.product.id,
          variantBarcode: item.variant.barcode,
          quantity: item.quantity,
          reason: 'Sale ($invoiceNumber)',
          movementReferenceId: sale.id,
          performedAt: 'POS',
        );
      }

      // Loyalty Transactions
      if (_selectedCustomer != null) {
        if (appliedRewardDiscount > 0) {
          final settings = repo.getLoyaltySettings();
          final redeemedPoints = appliedRewardDiscount / (settings.pointRedemptionValue > 0 ? settings.pointRedemptionValue : 1);
          await repo.addLoyaltyTransaction(
            customerId: _selectedCustomer!.id,
            saleId: sale.id,
            transactionType: 'Redeem',
            points: -redeemedPoints,
            monetaryValue: appliedRewardDiscount,
            reference: sale.invoiceNumber,
            createdBy: 'POS',
          );
        }

        if (sale.rewardPointsEarned > 0) {
          await repo.addLoyaltyTransaction(
            customerId: _selectedCustomer!.id,
            saleId: sale.id,
            transactionType: 'Earn',
            points: sale.rewardPointsEarned,
            monetaryValue: 0,
            reference: sale.invoiceNumber,
            createdBy: 'POS',
          );
        }
        
        _selectedCustomer!.lifetimeSpend += finalGrandTotal;
        await repo.saveCustomer(_selectedCustomer!);
      }

      // Refresh providers
      ProviderRefreshHelper.invalidateSalesProviders(ref);

      // Clear cart
      ref.read(cartProvider.notifier).clearCart();

      if (mounted) {
        // Navigate to Invoice Preview Screen, remove checkout and pos screens from stack
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => InvoicePreviewScreen(sale: sale)),
          (route) => route
              .isFirst, // Go back to dashboard effectively, but show invoice on top
        );
      }
    } catch (e) {
      debugPrint('Checkout error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to complete sale. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final customers = ref.watch(customersProvider);
    final repo = ref.watch(storageRepositoryProvider);

    double maxRedeemableValue = 0;
    double appliedRewardDiscount = 0;
    double finalGrandTotal = widget.grandTotal;

    if (_selectedCustomer != null) {
      maxRedeemableValue = repo.calculateMaxRedemptionValue(_selectedCustomer!.totalRewardPoints, widget.subtotal);
      if (_isRedeemingPoints) {
         appliedRewardDiscount = maxRedeemableValue;
         finalGrandTotal -= appliedRewardDiscount;
      }
    }
    
    finalGrandTotal -= _manualDiscount;
    if (finalGrandTotal < 0) finalGrandTotal = 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Processing sale and updating inventory...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer Selection
                  const Text(
                    'Select Customer',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<Customer?>(
                          initialValue: _selectedCustomer,
                          decoration: const InputDecoration(border: OutlineInputBorder()),
                          hint: const Text('Walk-In Customer'),
                          items: [
                            const DropdownMenuItem<Customer?>(
                              value: null,
                              child: Text('Walk-In Customer'),
                            ),
                            ...customers.map((c) => DropdownMenuItem(
                              value: c,
                              child: Text('${c.name} (${c.mobile})'),
                            )),
                          ],
                          onChanged: (val) => setState(() {
                            _selectedCustomer = val;
                            _isRedeemingPoints = false;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.person_add),
                        tooltip: 'Add New Customer',
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          final newCustomer = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CustomerFormScreen()),
                          );
                          if (newCustomer != null && newCustomer is Customer) {
                            setState(() {
                              _selectedCustomer = newCustomer;
                              _isRedeemingPoints = false;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_selectedCustomer != null)
                    CustomerRewardCard(
                      customer: _selectedCustomer!,
                      onClear: () => setState(() {
                        _selectedCustomer = null;
                        _isRedeemingPoints = false;
                      }),
                    ),
                  if (_selectedCustomer != null && _selectedCustomer!.totalRewardPoints > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: RewardDiscountWidget(
                        availablePoints: _selectedCustomer!.totalRewardPoints,
                        maxRedeemableValue: maxRedeemableValue,
                        isRedeeming: _isRedeemingPoints,
                        subtotal: widget.subtotal,
                        onChanged: (val) {
                          setState(() {
                            _isRedeemingPoints = val ?? false;
                          });
                        },
                      ),
                    ),
                  const SizedBox(height: 24),
                  
                  // Manual Discount
                  const Text(
                    'Manual Discount',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: _manualDiscount > 0 ? _manualDiscount.toString() : '',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Enter discount amount',
                      prefixText: '${settings.currencySymbol} ',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _manualDiscount = double.tryParse(val) ?? 0.0;
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  // Payment Summary Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Payment Summary',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Divider(),
                          _summaryRow(
                            'Subtotal',
                            '${settings.currencySymbol}${widget.subtotal}',
                          ),
                          if (widget.taxAmount > 0)
                            _summaryRow(
                              'Tax',
                              '${settings.currencySymbol}${widget.taxAmount}',
                            ),
                          if (appliedRewardDiscount > 0)
                            _summaryRow(
                              'Reward Discount',
                              '-${settings.currencySymbol}$appliedRewardDiscount',
                              color: Colors.green,
                            ),
                          if (_manualDiscount > 0)
                            _summaryRow(
                              'Manual Discount',
                              '-${settings.currencySymbol}$_manualDiscount',
                              color: Colors.orange,
                            ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Grand Total',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${settings.currencySymbol}$finalGrandTotal',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Payment Method
                  const Text(
                    'Payment Method',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _paymentMethods.map((method) {
                      final isSelected = _selectedPaymentMethod == method;
                      return InkWell(
                        onTap: () =>
                            setState(() => _selectedPaymentMethod = method),
                        child: Container(
                          width:
                              (MediaQuery.of(context).size.width - 44) /
                              2, // 2 columns
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withAlpha(40)
                                : Theme.of(context).cardColor,
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.withAlpha(50),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              method,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Customer Note
                  const Text(
                    'Notes (Optional)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'Add order notes here...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Confirm Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _processCheckout,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text(
                        'Confirm Sale',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 16, color: color ?? Colors.grey)),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
