import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/customer_stats.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

/// Identifies the person at the counter from their phone number.
///
/// A queue does not wait while a cashier scrolls a list of names, so the
/// number is the only thing that has to be typed. Once it matches, the card
/// below shows how often they have bought here — which is what the cashier
/// uses to decide the discount.
///
/// Typing letters instead of digits falls back to a name search, for the
/// customer who cannot remember which number they gave.
class CustomerLookupField extends ConsumerStatefulWidget {
  final Customer? selected;
  final ValueChanged<Customer?> onSelected;

  const CustomerLookupField({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  ConsumerState<CustomerLookupField> createState() =>
      _CustomerLookupFieldState();
}

class _CustomerLookupFieldState extends ConsumerState<CustomerLookupField> {
  final _controller = TextEditingController();
  final _nameController = TextEditingController();
  String _query = '';
  bool _isRegistering = false;

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _looksLikeNumber =>
      _query.isNotEmpty && RegExp(r'^[\d\s+\-()]+$').hasMatch(_query);

  String get _digits => StorageRepository.normaliseMobile(_query);

  void _onChanged(String value) {
    setState(() => _query = value);

    // A complete number resolves immediately — no button to press.
    if (StorageRepository.normaliseMobile(value).length == 10) {
      final match = ref.read(customerServiceProvider).findByMobile(value);
      if (match != null) _select(match);
    } else if (widget.selected != null) {
      widget.onSelected(null);
    }
  }

  void _select(Customer customer) {
    FocusScope.of(context).unfocus();
    _controller.clear();
    _nameController.clear();
    setState(() => _query = '');
    widget.onSelected(customer);
  }

  Future<void> _register() async {
    setState(() => _isRegistering = true);
    try {
      final customer = await ref
          .read(customerServiceProvider)
          .registerByMobile(_digits, name: _nameController.text);
      if (mounted) _select(customer);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeError(error, fallback: 'Could not save that customer.'),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;

    if (selected != null) {
      return _SelectedCustomerCard(
        customer: selected,
        stats: ref.watch(customerServiceProvider).statsFor(selected.id),
        currencySymbol: ref.watch(currencySymbolProvider),
        onClear: () => widget.onSelected(null),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.search,
          inputFormatters: [LengthLimitingTextInputFormatter(30)],
          decoration: InputDecoration(
            labelText: 'Mobile number',
            hintText: '10-digit number, or type a name',
            prefixIcon: const Icon(Icons.phone_outlined),
            border: const OutlineInputBorder(),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear',
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  ),
            helperText: _query.isEmpty
                ? 'Leave blank for a walk-in sale'
                : null,
          ),
          onChanged: _onChanged,
        ),
        if (_query.isNotEmpty) ...[
          const SizedBox(height: 10),
          _looksLikeNumber ? _numberResult(context) : _nameResults(context),
        ],
      ],
    );
  }

  Widget _numberResult(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = 10 - _digits.length;

    if (remaining > 0) {
      return _hint(
        context,
        Icons.keyboard,
        '$remaining more ${remaining == 1 ? 'digit' : 'digits'}',
        scheme.onSurfaceVariant,
      );
    }

    // Ten digits with no match: offer to register them in one tap.
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.person_add_alt, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'New customer · $_digits',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _register(),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _isRegistering ? null : _register,
              icon: _isRegistering
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text('Add and attach to this sale'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nameResults(BuildContext context) {
    final matches = ref
        .read(customerServiceProvider)
        .searchCustomers(_query)
        .take(6)
        .toList();

    if (matches.isEmpty) {
      return _hint(
        context,
        Icons.search_off,
        'Nobody matches "$_query"',
        Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final customer in matches)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                child: Text(
                  customer.name.isEmpty ? '?' : customer.name[0].toUpperCase(),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              title: Text(customer.name),
              subtitle: Text(customer.mobile),
              onTap: () => _select(customer),
            ),
        ],
      ),
    );
  }

  Widget _hint(
    BuildContext context,
    IconData icon,
    String message,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        // Hint text is a full sentence and the row has no slack of its own,
        // so on a 320px phone it ran off the side of the card.
        Expanded(
          child: Text(message, style: TextStyle(fontSize: 13, color: color)),
        ),
      ],
    );
  }
}

/// The history the cashier reads before choosing a discount.
class _SelectedCustomerCard extends StatelessWidget {
  final Customer customer;
  final CustomerVisitStats stats;
  final String currencySymbol;
  final VoidCallback onClear;

  const _SelectedCustomerCard({
    required this.customer,
    required this.stats,
    required this.currencySymbol,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final owes = customer.currentBalance > 0;
    final days = stats.daysSinceLastVisit;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      color: scheme.primaryContainer.withValues(alpha: 0.22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  child: Text(
                    customer.name.isEmpty
                        ? '?'
                        : customer.name[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        customer.mobile,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Change customer',
                  onPressed: onClear,
                ),
              ],
            ),

            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Tag(label: stats.standing, emphasis: true),
                _Tag(label: 'This is their ${stats.nextVisitLabel}'),
                if (days != null)
                  _Tag(
                    label: days == 0
                        ? 'Last bought today'
                        : days == 1
                        ? 'Last bought yesterday'
                        : 'Last bought $days days ago',
                  ),
              ],
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                _Metric(label: 'Purchases', value: Fmt.count(stats.visits)),
                _Metric(
                  label: 'Spent here',
                  value: Fmt.moneyCompact(stats.totalSpend, currencySymbol),
                ),
                _Metric(
                  label: 'Average bill',
                  value: Fmt.moneyCompact(stats.averageBasket, currencySymbol),
                ),
                if (customer.totalRewardPoints > 0)
                  _Metric(
                    label: 'Points',
                    value: Fmt.count(customer.totalRewardPoints),
                  ),
              ],
            ),

            if (owes) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Owes ${Fmt.money(customer.currentBalance, currencySymbol)} '
                  'from earlier bills',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final bool emphasis;

  const _Tag({required this.label, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: emphasis ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
          color: emphasis ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
