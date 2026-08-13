import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/customer_model.dart';
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

  /// Offered as one-tap chips; a cashier at a queue should not have to type.
  static const _discountPresets = [0.0, 5.0, 10.0, 15.0, 20.0];

  final _notesController = TextEditingController();
  final _discountController = TextEditingController();

  String _paymentMethod = 'Cash';
  Customer? _customer;
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
    paymentMethod: _paymentMethod,
    notes: _notesController.text.trim(),
    discountPercent: _discountPercent,
    redeemPoints: _redeemPoints,
    createdBy: 'POS',
  );

  Future<void> _confirmSale() async {
    // Re-entrancy guard. setState only schedules a rebuild, so two taps landing
    // in the same frame both reach here and bill the customer twice.
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
              Text('Recording sale and updating stock…'),
            ],
          ),
        ),
      );
    }

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
                _sectionTitle('Customer'),
                CustomerLookupField(
                  selected: _customer,
                  onSelected: (c) => setState(() {
                    _customer = c;
                    _redeemPoints = false;
                  }),
                ),
                if (_customer != null && loyalty.isLoyaltyEnabled)
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
                _sectionTitle('Payment method'),
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
                _sectionTitle('Notes'),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Optional note for this invoice',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _confirmSale,
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

  /// Turns the percentage into money as the cashier types, so the figure
  /// they are giving away is never left to mental arithmetic.
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
    return SegmentedButton<String>(
      segments: methods
          .map((m) => ButtonSegment(value: m, label: Text(m)))
          .toList(),
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (values) => onChanged(values.first),
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
  final dynamic settings;

  const _SummaryCard({required this.totals, required this.settings});

  @override
  Widget build(BuildContext context) {
    final symbol = settings.currencySymbol as String;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _row(context, 'Subtotal', Fmt.money(totals.subtotal, symbol)),
            if (totals.rewardDiscount > 0)
              _row(
                context,
                'Reward points',
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
            if (totals.taxAmount > 0)
              _row(
                context,
                settings.taxMode == TaxMode.inclusive
                    ? 'Tax (${settings.taxRate}% incl.)'
                    : 'Tax (${settings.taxRate}%)',
                Fmt.money(totals.taxAmount, symbol),
              ),
            const Divider(height: 28),
            Row(
              children: [
                Text('Total due', style: theme.textTheme.titleMedium),
                const SizedBox(width: 12),
                // The amount is set in a headline face, so on a 320px phone
                // the pair outgrew the card. It takes the remaining width and
                // shrinks to fit rather than overflowing — the figure the
                // customer pays must stay legible and whole.
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
                      'Earns ${Fmt.points(totals.pointsEarned)}',
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // The label yields space rather than pushing the amount off the
          // card; what the customer is charged must never be the part that
          // gets clipped.
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
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
