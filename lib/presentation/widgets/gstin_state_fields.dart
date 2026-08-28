import 'package:flutter/material.dart';

import 'package:atomid/domain/gst/gst_states.dart';

/// The GSTIN and state pair, for any party the shop trades with.
///
/// One widget for customers and suppliers so both are held to the same
/// standard: the same structural check, the same state list, the same wording.
/// Before this, a GSTIN was a free-text box on both forms — anything typed was
/// accepted and printed on the invoice — and neither form offered a state at
/// all, so the field that decides CGST/SGST versus IGST could never be filled.
///
/// Both fields are optional. A walk-in sale needs neither, and an unregistered
/// supplier has no GSTIN.
class GstinStateFields extends StatelessWidget {
  const GstinStateFields({
    super.key,
    required this.gstinController,
    required this.stateCode,
    required this.onStateChanged,
    required this.onGstinChanged,
    this.partyLabel = 'Party',
  });

  final TextEditingController gstinController;

  /// Two-digit code, or empty when no state has been recorded.
  final String stateCode;

  final ValueChanged<String> onStateChanged;

  /// Called on every keystroke so the parent can rebuild and refresh the
  /// status line under the field.
  final VoidCallback onGstinChanged;

  final String partyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gstin = gstinController.text.trim();
    final check = gstin.isEmpty
        ? null
        : GstStates.validateGstin(
            gstin,
            expectedStateCode: stateCode.isEmpty ? null : stateCode,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: gstinController,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'GSTIN (optional)',
            prefixIcon: const Icon(Icons.receipt_long),
            hintText: '22AAAAA0000A1Z5',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => onGstinChanged(),
          validator: (value) {
            final entered = (value ?? '').trim();
            // Optional: an unregistered party is normal.
            if (entered.isEmpty) return null;
            final result = GstStates.validateGstin(
              entered,
              expectedStateCode: stateCode.isEmpty ? null : stateCode,
            );
            return result.isValid ? null : result.message;
          },
        ),
        if (check != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                check.isValid
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                size: 16,
                color: check.isValid
                    ? Colors.green.shade700
                    : theme.colorScheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                // "Format valid", never "verified": nothing here has been
                // checked against the GST portal, and saying otherwise would
                // invite someone to trust a well-formed but fictitious number.
                child: Text(
                  check.isValid
                      ? 'GSTIN format valid (${check.stateName}). '
                            'Not verified with the GST portal.'
                      : check.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: check.isValid
                        ? Colors.green.shade700
                        : theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: stateCode.isEmpty ? '' : stateCode,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'State (Place of Supply)',
            prefixIcon: Icon(Icons.map_outlined),
            border: OutlineInputBorder(),
            helperText:
                'Decides CGST + SGST or IGST. Left blank, a valid GSTIN '
                'supplies it.',
            helperMaxLines: 2,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Not set')),
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
          onChanged: (value) => onStateChanged(value ?? ''),
        ),
      ],
    );
  }
}
