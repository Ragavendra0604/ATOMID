import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/domain/pricing.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

/// Reward programme configuration.
///
/// The whole loyalty feature — earn, redeem, the checkout widgets, the
/// customer rewards tab — was gated behind `isLoyaltyEnabled`, which nothing
/// could set. This is the switch.
class LoyaltySettingsScreen extends ConsumerStatefulWidget {
  const LoyaltySettingsScreen({super.key});

  @override
  ConsumerState<LoyaltySettingsScreen> createState() =>
      _LoyaltySettingsScreenState();
}

class _LoyaltySettingsScreenState extends ConsumerState<LoyaltySettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late bool _enabled;
  late final TextEditingController _spendPerPoint;
  late final TextEditingController _pointsPerSpend;
  late final TextEditingController _redemptionValue;
  late final TextEditingController _maxPercent;
  late final TextEditingController _minBill;

  @override
  void initState() {
    super.initState();
    final s = ref.read(loyaltySettingsProvider);
    _enabled = s.isLoyaltyEnabled;
    _spendPerPoint = TextEditingController(
      text: Fmt.amount(s.spendAmountForPoint),
    );
    _pointsPerSpend = TextEditingController(
      text: Fmt.amount(s.pointsEarnedPerSpend),
    );
    _redemptionValue = TextEditingController(
      text: Fmt.amount(s.pointRedemptionValue),
    );
    _maxPercent = TextEditingController(
      text: Fmt.amount(s.maxRedemptionPercentage),
    );
    _minBill = TextEditingController(
      text: Fmt.amount(s.minBillAmountForRedemption),
    );
  }

  @override
  void dispose() {
    _spendPerPoint.dispose();
    _pointsPerSpend.dispose();
    _redemptionValue.dispose();
    _maxPercent.dispose();
    _minBill.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  LoyaltySettingsModel _draft() => LoyaltySettingsModel(
    isLoyaltyEnabled: _enabled,
    spendAmountForPoint: _num(_spendPerPoint),
    pointsEarnedPerSpend: _num(_pointsPerSpend),
    pointRedemptionValue: _num(_redemptionValue),
    maxRedemptionPercentage: _num(_maxPercent),
    minBillAmountForRedemption: _num(_minBill),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(storageRepositoryProvider).saveLoyaltySettings(_draft());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _enabled
              ? 'Reward programme is on.'
              : 'Reward programme is off. Existing points are kept.',
        ),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final symbol = ref.watch(currencySymbolProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reward points'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: ResponsivePadding.getScreenPadding(context),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: SwitchListTile(
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                        title: const Text(
                          'Reward programme',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Customers earn points on purchases and can spend '
                          'them as a discount.',
                        ),
                        secondary: const Icon(Icons.card_giftcard),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _enabled ? 1 : 0.45,
                      child: IgnorePointer(
                        ignoring: !_enabled,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _heading('Earning'),
                            Row(
                              children: [
                                Expanded(
                                  child: _numberField(
                                    _spendPerPoint,
                                    'Spend of',
                                    prefix: '$symbol ',
                                    min: 1,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _numberField(
                                    _pointsPerSpend,
                                    'Earns points',
                                    min: 0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _heading('Redeeming'),
                            _numberField(
                              _redemptionValue,
                              'One point is worth',
                              prefix: '$symbol ',
                              min: 0,
                            ),
                            const SizedBox(height: 12),
                            _numberField(
                              _maxPercent,
                              'Maximum share of a bill payable with points',
                              suffix: '%',
                              min: 0,
                              max: 100,
                            ),
                            const SizedBox(height: 12),
                            _numberField(
                              _minBill,
                              'Minimum bill to allow redemption',
                              prefix: '$symbol ',
                              min: 0,
                            ),
                            const SizedBox(height: 24),
                            _PreviewCard(
                              settings: _draft(),
                              currencySymbol: symbol,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save reward settings'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  Widget _numberField(
    TextEditingController controller,
    String label, {
    String? prefix,
    String? suffix,
    double min = 0,
    double? max,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
      validator: (value) {
        if (!_enabled) return null;
        final parsed = double.tryParse(value?.trim() ?? '');
        if (parsed == null) return 'Enter a number';
        if (parsed < min) return 'Must be at least ${Fmt.amount(min)}';
        if (max != null && parsed > max) {
          return 'Must be ${Fmt.amount(max)} or less';
        }
        return null;
      },
    );
  }
}

/// Shows the rules applied to a concrete bill, so the numbers above are not
/// abstract when the owner is deciding what to set.
class _PreviewCard extends StatelessWidget {
  final LoyaltySettingsModel settings;
  final String currencySymbol;

  const _PreviewCard({required this.settings, required this.currencySymbol});

  @override
  Widget build(BuildContext context) {
    const sampleBill = 1000.0;
    final earned = SalePricing.pointsEarned(
      loyalty: settings,
      payableAmount: sampleBill,
    );
    final redeemable = SalePricing.maxRedeemableValue(
      loyalty: settings,
      availablePoints: 500,
      subtotal: sampleBill,
    );

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'On a ${Fmt.money(sampleBill, currencySymbol)} bill',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('· The customer earns ${Fmt.points(earned)}.'),
            Text(
              '· A customer holding 500 points could take '
              '${Fmt.money(redeemable, currencySymbol)} off.',
            ),
          ],
        ),
      ),
    );
  }
}
