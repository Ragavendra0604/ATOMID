import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/presentation/features/auth/auth_screen.dart';
import 'package:atomid/presentation/features/settings/advanced_settings_screen.dart';
import 'package:atomid/presentation/features/settings/backup_screen.dart';
import 'package:atomid/presentation/features/settings/company_profile_screen.dart';
import 'package:atomid/domain/invoice_template.dart';
import 'package:atomid/presentation/features/settings/invoice_settings_screen.dart';
import 'package:atomid/presentation/features/settings/invoice_template_screen.dart';
import 'package:atomid/presentation/features/settings/loyalty_settings_screen.dart';
import 'package:atomid/presentation/features/hardware/hardware_settings_screen.dart';
import 'package:atomid/presentation/features/hardware/hardware_diagnostics_screen.dart';
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
  late String _pdfPageSize;
  late bool _roundOffEnabled;
  late bool _hsnRequired;
  late bool _showGstBreakdown;
  late bool _showHsnSummary;
  late String _thermalReceiptSize;
  late bool _showTaxOnThermalReceipt;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _storeName = TextEditingController(text: settings.companyName);
    _currency = TextEditingController(text: settings.currencySymbol);
    _pdfPageSize = settings.pdfPageSize;
    _roundOffEnabled = settings.roundOffEnabled;
    _hsnRequired = settings.hsnRequired;
    _showGstBreakdown = settings.showGstBreakdown;
    _showHsnSummary = settings.showHsnSummary;
    _thermalReceiptSize = settings.thermalReceiptSize;
    _showTaxOnThermalReceipt = settings.showTaxOnThermalReceipt;
  }

  @override
  void dispose() {
    _storeName.dispose();
    _currency.dispose();
    super.dispose();
  }

  SettingsModel _draft({bool? isDarkMode}) {
    return ref
        .read(settingsProvider)
        .copyWith(
          isDarkMode: isDarkMode,
          companyName: _storeName.text.trim(),
          currencySymbol: _currency.text.trim(),
          pdfPageSize: _pdfPageSize,
          roundOffEnabled: _roundOffEnabled,
          hsnRequired: _hsnRequired,
          showGstBreakdown: _showGstBreakdown,
          showHsnSummary: _showHsnSummary,
          thermalReceiptSize: _thermalReceiptSize,
          showTaxOnThermalReceipt: _showTaxOnThermalReceipt,
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
                    _heading('Store Information'),
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

                    _heading('GST & Pricing Engine'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _roundOffEnabled,
                              onChanged: (val) =>
                                  setState(() => _roundOffEnabled = val),
                              title: const Text('Automatic Invoice Round-Off'),
                              subtitle: const Text(
                                'Rounds final payable bill amount to nearest integer (e.g. ₹599.40 → ₹599.00).',
                              ),
                            ),
                            const SizedBox(height: 16),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _hsnRequired,
                              onChanged: (val) =>
                                  setState(() => _hsnRequired = val),
                              title: const Text(
                                'Mandatory HSN on Product Entry',
                              ),
                              subtitle: const Text(
                                'Blocks saving a product without a valid HSN code.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),
                    _link(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'Advanced System Setup (Admin Only)',
                      subtitle:
                          'Tax mode, GST presets, Point of Supply policy, and rounding',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdvancedSettingsScreen(),
                          ),
                        ).then((_) {
                          // refresh values if changed
                          final settings = ref.read(settingsProvider);
                          setState(() {
                            _roundOffEnabled = settings.roundOffEnabled;
                            _hsnRequired = settings.hsnRequired;
                          });
                        });
                      },
                    ),

                    _heading('Receipt & Invoice Display'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _showGstBreakdown,
                              onChanged: (val) =>
                                  setState(() => _showGstBreakdown = val),
                              title: const Text('Print GST Summary Table'),
                              subtitle: const Text(
                                'Prints the rate-wise CGST and SGST summary at the '
                                'foot of the A4 invoice.',
                              ),
                            ),
                            const Divider(height: 24),
                            DropdownButtonFormField<String>(
                              initialValue: _thermalReceiptSize,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Thermal POS Printer Paper Width',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: '80mm',
                                  child: Text(
                                    '80mm (Standard POS Thermal Receipt)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: '58mm',
                                  child: Text(
                                    '58mm (Compact Mobile Thermal Receipt)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _thermalReceiptSize = v);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _showTaxOnThermalReceipt,
                              onChanged: (val) => setState(
                                () => _showTaxOnThermalReceipt = val,
                              ),
                              title: const Text(
                                'Show Tax Summary on Thermal Receipt',
                              ),
                              subtitle: const Text(
                                'Prints compact GST & Taxable breakdown on thermal slips.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    _heading('Appearance & Formats'),
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
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'PDF Document Page Size',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'A4',
                              child: Text(
                                'A4',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Letter',
                              child: Text(
                                'Letter',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _pdfPageSize = v);
                          },
                        ),
                      ),
                    ),

                    _heading('Hardware & Peripherals'),
                    _link(
                      icon: Icons.print_outlined,
                      title: 'Terminal Hardware Setup',
                      subtitle:
                          'Configure barcode scanners, receipt printers, and label printers for this specific terminal.',
                      onTap: () => _open(const HardwareSettingsScreen()),
                    ),
                    _link(
                      icon: Icons.monitor_heart_outlined,
                      title: 'Hardware Diagnostics',
                      subtitle:
                          'Test connection status of configured hardware devices.',
                      onTap: () => _open(const HardwareDiagnosticsScreen()),
                    ),

                    _heading('Configure Modules'),
                    _link(
                      icon: Icons.business_outlined,
                      title: 'Business Details & Shop State',
                      subtitle:
                          'Legal name, shop GSTIN, state code, address and logo',
                      onTap: () => _open(const CompanyProfileScreen()),
                    ),
                    _link(
                      icon: Icons.dashboard_customize_outlined,
                      title: 'Invoice Template',
                      subtitle:
                          'Prints on every bill — currently '
                          '${InvoiceTemplate.fromId(ref.watch(settingsProvider).invoiceTemplate).label}',
                      onTap: () => _open(const InvoiceTemplateScreen()),
                    ),
                    _link(
                      icon: Icons.receipt_long_outlined,
                      title: 'Invoice Layout & UPI QR',
                      subtitle:
                          'Footer text, payment terms and instant UPI QR code',
                      onTap: () => _open(const InvoiceSettingsScreen()),
                    ),
                    _link(
                      icon: Icons.card_giftcard_outlined,
                      title: 'Customer Reward Points',
                      subtitle:
                          ref.watch(loyaltySettingsProvider).isLoyaltyEnabled
                          ? 'On — earning and redemption rules'
                          : 'Off — customers are not earning points',
                      onTap: () => _open(const LoyaltySettingsScreen()),
                    ),
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

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Syncing will pause. Your products, sales and settings will stay on '
          'this device, and you can sign back in at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay signed in'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authServiceProvider).signOut();
    }
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _heading(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8, left: 4),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

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

class _AboutFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'AtomID Store POS • Single Retail Shop Edition',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
