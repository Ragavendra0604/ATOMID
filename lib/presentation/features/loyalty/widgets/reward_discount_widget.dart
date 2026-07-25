import 'package:flutter/material.dart';

class RewardDiscountWidget extends StatelessWidget {
  final double availablePoints;
  final double maxRedeemableValue;
  final bool isRedeeming;
  final ValueChanged<bool?> onChanged;
  final double subtotal;

  const RewardDiscountWidget({
    super.key,
    required this.availablePoints,
    required this.maxRedeemableValue,
    required this.isRedeeming,
    required this.onChanged,
    required this.subtotal,
  });

  @override
  Widget build(BuildContext context) {
    if (availablePoints <= 0 || maxRedeemableValue <= 0) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.card_giftcard, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text(
                        'Redeem Reward Points',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Available: ${availablePoints.toStringAsFixed(0)} pts\nMax discount: ₹${maxRedeemableValue.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: isRedeeming,
              onChanged: onChanged,
              activeColor: Theme.of(context).colorScheme.primary,
            )
          ],
        ),
      ),
    );
  }
}
