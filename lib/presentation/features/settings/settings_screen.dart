import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/pricing.dart';
import 'package:atomid/presentation/features/auth/auth_screen.dart';
import 'package:atomid/presentation/features/settings/backup_screen.dart';
import 'package:atomid/presentation/features/settings/company_profile_screen.dart';
import 'package:atomid/presentation/features/settings/invoice_settings_screen.dart';
import 'package:atomid/presentation/features/settings/loyalty_settings_screen.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _storeName;
  late final TextEditingController _currency;
  late final TextEditingController _taxRate;
  late String _pdfPageSize;
  late String _taxMode;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _storeName = TextEditingController(text: settings.companyName);
    _currency = TextEditingController(text: settings.currencySymbol);
    _taxRate = TextEditingController(text: Fmt.amount(settings.taxRate));
    _pdfPageSize = settings.pdfPageSize;
    _taxMode = settings.taxMode;
  }

  @override
  void dispose() {
    _storeName.dispose();
    _currency.dispose();
    _taxRate.dispose();
    super.dispose();
  }

  /// Builds the next settings record by copying the *current* stored record.
  ///
  /// Constructing a fresh model from only the visible fields silently reset
  /// tax on every save and on every dark-mode toggle.
  SettingsModel _draft({bool? isDarkMode}) {
    return ref
        .read(settingsProvider)
        .copyWith(
          isDarkMode: isDarkMode,
          companyName: _storeName.text.trim(),
          currencySymbol: _currency.text.trim(),
          pdfPageSize: _pdfPageSize,
          taxMode: _taxMode,
          taxRate: double.tryParse(_taxRate.text.trim()),
        );
  }

  Future<void> _save({bool showToast = true}) async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(storageRepositoryProvider).saveSettings(_draft());

    if (!mounted || !showToast) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settings saved.')));
  }

  Future<void> _setDarkMode(bool value) async {
    await ref
        .read(storageRepositoryProvider)
        .saveSettings(_draft(isDarkMode: value));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    // How the shop trades versus how the app is plumbed. Separating the two

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _heading('Store'),
                    TextFormField(
                      controller: _storeName,
                      decoration: const InputDecoration(
                        labelText: 'Store name',
                        prefixIcon: Icon(Icons.storefront_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Store name is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _currency,
                      decoration: const InputDecoration(
                        labelText: 'Currency symbol',
                        hintText: '₹, \$, £, €',
                        prefixIcon: Icon(Icons.payments_outlined),
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 3,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Currency symbol is required'
                          : null,
                    ),

                    _heading('Tax'),
                    TextFormField(
                      controller: _taxRate,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Tax rate',
                        suffixText: '%',
                        prefixIcon: Icon(Icons.percent),
                        border: OutlineInputBorder(),
                        helperText: 'Set 0 if you do not charge tax.',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final parsed = double.tryParse(value?.trim() ?? '');
                        if (parsed == null) return 'Enter a number';
                        if (parsed < 0 || parsed > 100) {
                          return 'Must be between 0 and 100';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _TaxModeSelector(
                      mode: _taxMode,
                      onChanged: (mode) => setState(() => _taxMode = mode),
                    ),

                    _heading('Appearance'),
                    // A "Enable Biometric Login" switch used to sit below dark
                    // mode. It saved its state, synced it, and was carefully
                    // preserved across restores — and nothing ever read it.
                    // There is no lock anywhere in this app, so the control
                    // told the owner their till was protected when it was not.
                    // Removed rather than left as a promise the code does not
                    // keep; see the security note in README.
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: settings.isDarkMode,
                            onChanged: _setDarkMode,
                            title: const Text('Dark mode'),
                            secondary: Icon(
                              settings.isDarkMode
                                  ? Icons.dark_mode_outlined
                                  : Icons.light_mode_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: DropdownButtonFormField<String>(
                          initialValue: _pdfPageSize,
                          decoration: const InputDecoration(
                            labelText: 'PDF page size',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'A4', child: Text('A4')),
                            DropdownMenuItem(
                              value: 'Letter',
                              child: Text('Letter'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _pdfPageSize = v);
                          },
                        ),
                      ),
                    ),

                    _heading('Configure'),
                    _link(
                      icon: Icons.business_outlined,
                      title: 'Business details',
                      subtitle:
                          'Name, address, GST and logo printed on invoices',
                      onTap: () => _open(const CompanyProfileScreen()),
                    ),
                    _link(
                      icon: Icons.receipt_long_outlined,
                      title: 'Invoice layout',
                      subtitle: 'Footer text, terms and UPI QR code',
                      onTap: () => _open(const InvoiceSettingsScreen()),
                    ),
                    _link(
                      icon: Icons.card_giftcard_outlined,
                      title: 'Reward points',
                      subtitle:
                          ref.watch(loyaltySettingsProvider).isLoyaltyEnabled
                          ? 'On — earning and redemption rules'
                          : 'Off — customers are not earning points',
                      onTap: () => _open(const LoyaltySettingsScreen()),
                    ),
                    // Signing in is only ever about the cloud copy. Nothing
                    // on this device is locked behind it.
                    _link(
                      icon: ref.watch(isSignedInProvider)
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      title: ref.watch(isSignedInProvider)
                          ? 'Cloud backup is on'
                          : 'Back up to the cloud',
                      subtitle:
                          ref.watch(authServiceProvider).currentUser?.email ??
                          'Sign in to sync this device when it is online',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AuthScreen()),
                      ),
                    ),
                    if (ref.watch(isSignedInProvider))
                      _link(
                        icon: Icons.logout,
                        title: 'Sign out',
                        subtitle:
                            'Stops syncing. Everything stays on this device.',
                        onTap: _signOut,
                      ),

                    // A backup is not the same thing as sync. Sync mirrors a
                    // mistake; a backup is a point you can go back to.
                    _link(
                      icon: Icons.save_alt_outlined,
                      title: 'Backup and restore',
                      subtitle: 'Save a copy of everything, or put one back',
                      onTap: () => _open(const BackupScreen()),
                    ),

                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save settings'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _AboutFooter(),
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

  /// Detaches this device from the cloud copy.
  ///
  /// Nothing local is touched — the records, the settings and the queue all
  /// stay put. Signing back in resumes uploading exactly where it left off.
  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop backing up?'),
        content: const Text(
          'This device keeps all of its data and carries on working. '
          'It just will not sync until you sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(authServiceProvider).signOut();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Signed out. Working on this device only.')),
    );
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
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

  Widget _link({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _TaxModeSelector extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;

  const _TaxModeSelector({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: TaxMode.inclusive, label: Text('Included')),
            ButtonSegment(value: TaxMode.exclusive, label: Text('Added on')),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (values) => onChanged(values.first),
        ),
        const SizedBox(height: 8),
        Text(
          mode == TaxMode.inclusive
              ? 'Shelf prices already contain tax. The customer pays the '
                    'marked price and the invoice shows the tax within it.'
              : 'Tax is calculated on the discounted subtotal and added to '
                    'the total the customer pays.',
          style: TextStyle(
            fontSize: 12.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AboutFooter extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionServiceProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Divider(color: scheme.outlineVariant),
        const SizedBox(height: 12),
        Text(
          'Atomid · version 1.0.0',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          'Device ${session.deviceId.split('_').last}',
          style: TextStyle(fontSize: 11, color: scheme.outline),
        ),
      ],
    );
  }
}
