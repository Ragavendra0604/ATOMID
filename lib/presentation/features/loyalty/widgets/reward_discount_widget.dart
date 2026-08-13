import 'package:flutter/material.dart';

import 'package:atomid/core/utils/formatters.dart';

/// Offers the customer's reward points as a discount on this sale.
class RewardDiscountWidget extends StatelessWidget {
  final double availablePoints;
  final double maxRedeemableValue;
  final bool isRedeeming;
  final String currencySymbol;
  final ValueChanged<bool?> onChanged;

  const RewardDiscountWidget({
    super.key,
    required this.availablePoints,
    required this.maxRedeemableValue,
    required this.isRedeeming,
    required this.currencySymbol,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canRedeem = availablePoints > 0 && maxRedeemableValue > 0;

    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: SwitchListTile(
        value: isRedeeming && canRedeem,
        onChanged: canRedeem ? onChanged : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        secondary: Icon(Icons.card_giftcard, color: scheme.primary),
        title: const Text(
          'Redeem reward points',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          canRedeem
              ? '${Fmt.points(availablePoints)} available · saves up to '
                    '${Fmt.money(maxRedeemableValue, currencySymbol)}'
              : availablePoints <= 0
              ? 'No points earned yet'
              : 'This bill is below the minimum for redemption',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}
