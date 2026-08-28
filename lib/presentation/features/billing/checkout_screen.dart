import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/gst/gst_states.dart';
import 'package:atomid/domain/pricing.dart';
import 'package:atomid/domain/services/sale_service.dart';
import 'package:atomid/presentation/features/billing/invoice_preview_screen.dart';
import 'package:atomid/presentation/features/billing/widgets/customer_lookup_field.dart';
import 'package:atomid/presentation/features/loyalty/widgets/reward_discount_widget.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/providers/cart_notifier.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  static const _paymentMethods = ['Cash', 'UPI', 'Card', 'Credit'];
  static const _discountPresets = [0.0, 5.0, 10.0, 15.0, 20.0];

  final _notesController = TextEditingController();
  final _discountController = TextEditingController();

  String _paymentMethod = 'Cash';
  Customer? _customer;
  String? _destinationStateCode;
  bool _redeemPoints = false;
  double _discountPercent = 0;
  bool _isProcessing = false;

  @override
  void dispose() {
    _notesController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  CheckoutRequest _buildRequest() => CheckoutRequest(
    items: ref.read(cartProvider),
    customer: _customer,
    destinationStateCode: _destinationStateCode,
    paymentMethod: _paymentMethod,
    notes: _notesController.text.trim(),
    discountPercent: _discountPercent,
    redeemPoints: _redeemPoints,
    createdBy: 'POS',
  );

  Future<void> _confirmSale() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final sale = await ref
          .read(saleServiceProvider)
          .checkout(_buildRequest());

      ref.read(cartProvider.notifier).clearCart();

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => InvoicePreviewScreen(sale: sale)),
        (route) => route.isFirst,
      );
    } catch (error, stack) {
      debugPrint('Checkout error: $error\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeError(
              error,
              fallback: 'The sale could not be completed. Nothing was charged.',
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _setDiscount(double percent) {
    setState(() {
      _discountPercent = percent;
      _discountController.text = percent == 0 ? '' : Fmt.amount(percent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final loyalty = ref.watch(loyaltySettingsProvider);
    final totals = ref.read(saleServiceProvider).preview(_buildRequest());

    if (_isProcessing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Recording sale and freezing tax snapshot…'),
            ],
          ),
        ),
      );
    }

    final hasTaxIssues = totals.gstResult != null && !totals.gstResult!.isValid;
    final isGstinValid =
        _customer?.gstNumber.isNotEmpty == true &&
        GstStates.isValidGstin(_customer!.gstNumber);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SingleChildScrollView(
        padding: ResponsivePadding.getScreenPadding(context),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasTaxIssues)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade800),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            totals.gstResult!.errors.join('\n'),
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                _sectionTitle('Customer (Optional for Walk-in)'),
                CustomerLookupField(
                  selected: _customer,
                  onSelected: (c) => setState(() {
                    _customer = c;
                    _redeemPoints = false;
                    if (c != null && c.stateCode.isNotEmpty) {
                      _destinationStateCode = c.stateCode;
                    }
                  }),
                ),
                if (_customer != null) ...[
                  if (_customer!.gstNumber.isNotEmpty)
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
                          Expanded(
                            child: Text(
                              isGstinValid
                                  ? 'B2B GSTIN format valid (${_customer!.gstNumber})'
                                  : 'GSTIN format incomplete (${_customer!.gstNumber})',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isGstinValid
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (loyalty.isLoyaltyEnabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: RewardDiscountWidget(
                        availablePoints: _customer!.totalRewardPoints,
                        maxRedeemableValue: SalePricing.maxRedeemableValue(
                          loyalty: loyalty,
                          availablePoints: _customer!.totalRewardPoints,
                          subtotal: totals.subtotal,
                        ),
                        isRedeeming: _redeemPoints,
                        currencySymbol: settings.currencySymbol,
                        onChanged: (value) =>
                            setState(() => _redeemPoints = value ?? false),
                      ),
                    ),
                ],

                if (settings.walkInPosPolicy == 'ASK_AT_CHECKOUT' ||
                    (_customer?.state.isNotEmpty == true)) ...[
                  const SizedBox(height: 20),
                  _sectionTitle('Place of Supply (Destination)'),
                  DropdownButtonFormField<String>(
                    initialValue:
                        _destinationStateCode ??
                        (_customer?.stateCode.isNotEmpty == true
                            ? _customer!.stateCode
                            : null),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Place of Supply (Delivery State)',
                      border: OutlineInputBorder(),
                      helperText:
                          'Determines whether bill is Intra-State (CGST+SGST) or Inter-State (IGST)',
                    ),
                    items: GstStates.allStates.map((s) {
                      return DropdownMenuItem(
                        value: s.code,
                        child: Text(
                          '${s.name} (${s.code})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) =>
                        setState(() => _destinationStateCode = val),
                  ),
                ],

                const SizedBox(height: 28),
                _sectionTitle('Discount'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final preset in _discountPresets)
                      ChoiceChip(
                        label: Text(
                          preset == 0 ? 'None' : '${preset.toInt()}%',
                        ),
                        selected: _discountPercent == preset,
                        onSelected: (_) => _setDiscount(preset),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _discountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Discount',
                    hintText: '0',
                    suffixText: '%',
                    prefixIcon: const Icon(Icons.percent),
                    border: const OutlineInputBorder(),
                    helperText: _discountHelper(
                      totals,
                      settings.currencySymbol,
                    ),
                  ),
                  onChanged: (value) => setState(
                    () => _discountPercent = double.tryParse(value) ?? 0,
                  ),
                ),

                const SizedBox(height: 28),
                _sectionTitle('Payment Method'),
                const SizedBox(height: 4),
                _PaymentMethodSelector(
                  methods: _paymentMethods,
                  selected: _paymentMethod,
                  onChanged: (m) => setState(() => _paymentMethod = m),
                ),
                if (_paymentMethod == 'Credit')
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _CreditNotice(
                      customer: _customer,
                      projected:
                          (_customer?.currentBalance ?? 0) + totals.grandTotal,
                      currencySymbol: settings.currencySymbol,
                    ),
                  ),

                const SizedBox(height: 28),
                _SummaryCard(totals: totals, settings: settings),

                const SizedBox(height: 28),
                _sectionTitle('Notes / Remarks'),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Optional note printed on this invoice',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: hasTaxIssues ? null : _confirmSale,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    'Charge ${Fmt.money(totals.grandTotal, settings.currencySymbol)}',
                    style: const TextStyle(fontSize: 17),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _discountHelper(SaleTotals totals, String symbol) {
    if (_discountPercent <= 0) return null;
    if (totals.discountPercent < _discountPercent) {
      return 'Capped at ${totals.discountPercent}% '
          '(${Fmt.money(totals.manualDiscount, symbol)}) — a discount cannot '
          'exceed the amount due.';
    }
    return 'Takes ${Fmt.money(totals.manualDiscount, symbol)} off this bill.';
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  );
}

class _PaymentMethodSelector extends StatelessWidget {
  final List<String> methods;
  final String selected;
  final ValueChanged<String> onChanged;

  const _PaymentMethodSelector({
    required this.methods,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: methods.map((m) {
        final isSelected = selected == m;
        return ChoiceChip(
          label: Text(m),
          selected: isSelected,
          onSelected: (_) => onChanged(m),
        );
      }).toList(),
    );
  }
}

class _CreditNotice extends StatelessWidget {
  final Customer? customer;
  final double projected;
  final String currencySymbol;

  const _CreditNotice({
    required this.customer,
    required this.projected,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (customer == null) {
      return _notice(
        context,
        scheme.error,
        Icons.error_outline,
        'Select a customer to sell on credit.',
      );
    }

    final limit = customer!.creditLimit;
    if (limit <= 0) {
      return _notice(
        context,
        scheme.outline,
        Icons.info_outline,
        'No credit limit set for ${customer!.name}.',
      );
    }

    final overLimit = projected > limit;
    return _notice(
      context,
      overLimit ? scheme.error : scheme.primary,
      overLimit ? Icons.block : Icons.credit_score,
      overLimit
          ? 'Over limit: ${Fmt.money(projected, currencySymbol)} of '
                '${Fmt.money(limit, currencySymbol)} allowed.'
          : 'Balance after this sale: ${Fmt.money(projected, currencySymbol)} '
                'of ${Fmt.money(limit, currencySymbol)}.',
    );
  }

  Widget _notice(
    BuildContext context,
    Color color,
    IconData icon,
    String message,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final SaleTotals totals;
  final SettingsModel settings;

  const _SummaryCard({required this.totals, required this.settings});

  @override
  Widget build(BuildContext context) {
    final symbol = settings.currencySymbol;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Tax & Invoice Breakdown',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (totals.placeOfSupply.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'POS: ${totals.placeOfSupply} (${totals.isInterState ? "Inter-State" : "Intra-State"})',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _row(context, 'Gross Subtotal', Fmt.money(totals.subtotal, symbol)),
            if (totals.rewardDiscount > 0)
              _row(
                context,
                'Reward Points Discount',
                '−${Fmt.money(totals.rewardDiscount, symbol)}',
                color: Colors.green.shade700,
              ),
            if (totals.manualDiscount > 0)
              _row(
                context,
                'Discount (${totals.discountPercent}%)',
                '−${Fmt.money(totals.manualDiscount, symbol)}',
                color: Colors.orange.shade800,
              ),
            if (totals.taxableAmount > 0)
              _row(
                context,
                'Net Taxable Value',
                Fmt.money(totals.taxableAmount, symbol),
              ),
            if (totals.isInterState) ...[
              if (totals.igstAmount > 0)
                _row(
                  context,
                  'Integrated GST (IGST)',
                  Fmt.money(totals.igstAmount, symbol),
                ),
            ] else ...[
              if (totals.cgstAmount > 0)
                _row(
                  context,
                  'Central GST (CGST)',
                  Fmt.money(totals.cgstAmount, symbol),
                ),
              if (totals.isUtgst && totals.utgstAmount > 0)
                _row(
                  context,
                  'Union Territory GST (UTGST)',
                  Fmt.money(totals.utgstAmount, symbol),
                )
              else if (totals.sgstAmount > 0)
                _row(
                  context,
                  'State GST (SGST)',
                  Fmt.money(totals.sgstAmount, symbol),
                ),
            ],
            if (totals.cessAmount > 0)
              _row(
                context,
                'Compensation Cess',
                Fmt.money(totals.cessAmount, symbol),
              ),
            if (totals.roundOff != 0.0)
              _row(
                context,
                'Round-Off Adjustment',
                '${totals.roundOff >= 0 ? "+" : ""}${Fmt.money(totals.roundOff, symbol)}',
                color: Colors.blueGrey,
              ),
            const Divider(height: 24),
            Row(
              children: [
                Text('Payable Amount', style: theme.textTheme.titleMedium),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      Fmt.money(totals.grandTotal, symbol),
                      maxLines: 1,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (totals.pointsEarned > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.card_giftcard,
                      size: 14,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Customer earns ${Fmt.points(totals.pointsEarned)} points',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
