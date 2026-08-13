import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:atomid/core/utils/image_provider_utils.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

/// Business details printed on every invoice, receipt and report.
///
/// Nothing could write [CompanyModel] before this screen existed, so every
/// generated PDF carried the placeholder "Company Name" with no address or GST.
class CompanyProfileScreen extends ConsumerStatefulWidget {
  const CompanyProfileScreen({super.key});

  @override
  ConsumerState<CompanyProfileScreen> createState() =>
      _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends ConsumerState<CompanyProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  String _logoPath = '';
  bool _isDirty = false;

  static const _labels = {
    'name': 'Business name',
    'ownerName': 'Owner name',
    'phone1': 'Primary phone',
    'phone2': 'Secondary phone',
    'email': 'Email',
    'website': 'Website',
    'gstNumber': 'GST number',
    'panNumber': 'PAN number',
    'address': 'Street address',
    'city': 'City',
    'state': 'State',
    'pincode': 'PIN code',
    'country': 'Country',
    'invoicePrefix': 'Invoice prefix',
    'financialYear': 'Financial year',
  };

  @override
  void initState() {
    super.initState();
    final company = ref.read(companyProvider);
    _logoPath = company.logoPath;
    _fields = {
      'name': TextEditingController(text: company.name),
      'ownerName': TextEditingController(text: company.ownerName),
      'phone1': TextEditingController(text: company.phone1),
      'phone2': TextEditingController(text: company.phone2),
      'email': TextEditingController(text: company.email),
      'website': TextEditingController(text: company.website),
      'gstNumber': TextEditingController(text: company.gstNumber),
      'panNumber': TextEditingController(text: company.panNumber),
      'address': TextEditingController(text: company.address),
      'city': TextEditingController(text: company.city),
      'state': TextEditingController(text: company.state),
      'pincode': TextEditingController(text: company.pincode),
      'country': TextEditingController(text: company.country),
      'invoicePrefix': TextEditingController(text: company.invoicePrefix),
      'financialYear': TextEditingController(text: company.financialYear),
    };
    for (final controller in _fields.values) {
      controller.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _value(String key) => _fields[key]!.text.trim();

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _logoPath = picked.path;
        _isDirty = true;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final company = CompanyModel(
      name: _value('name'),
      logoPath: _logoPath,
      ownerName: _value('ownerName'),
      gstNumber: _value('gstNumber'),
      panNumber: _value('panNumber'),
      phone1: _value('phone1'),
      phone2: _value('phone2'),
      email: _value('email'),
      website: _value('website'),
      address: _value('address'),
      city: _value('city'),
      state: _value('state'),
      country: _value('country'),
      pincode: _value('pincode'),
      invoicePrefix: _value('invoicePrefix').isEmpty
          ? 'INV'
          : _value('invoicePrefix'),
      barcodePrefix: ref.read(companyProvider).barcodePrefix,
      currency: ref.read(settingsProvider).currencySymbol,
      financialYear: _value('financialYear'),
    );

    await ref.read(storageRepositoryProvider).saveCompany(company);

    if (!mounted) return;
    setState(() => _isDirty = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Business details saved.')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (discard && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Business details'),
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
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _logoPicker(context),
                      const SizedBox(height: 28),
                      _group('Identity', [
                        _field('name', required: true),
                        _field('ownerName'),
                      ]),
                      _group('Contact', [
                        _field('phone1', keyboard: TextInputType.phone),
                        _field('phone2', keyboard: TextInputType.phone),
                        _field(
                          'email',
                          keyboard: TextInputType.emailAddress,
                          validator: _validateEmail,
                        ),
                        _field('website'),
                      ]),
                      _group('Tax registration', [
                        _field('gstNumber'),
                        _field('panNumber'),
                      ]),
                      _group('Address', [
                        _field('address', maxLines: 2),
                        Row(
                          children: [
                            Expanded(child: _field('city')),
                            const SizedBox(width: 12),
                            Expanded(child: _field('state')),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _field(
                                'pincode',
                                keyboard: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: _field('country')),
                          ],
                        ),
                      ]),
                      _group('Documents', [
                        _field(
                          'invoicePrefix',
                          helper:
                              'Invoices are numbered PREFIX-DATE-DEVICE-0001',
                        ),
                        _field('financialYear', helper: 'e.g. 2026–27'),
                      ]),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save business details'),
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
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits to the business details will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _logoPicker(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
            image: _logoPath.isEmpty
                ? null
                : DecorationImage(
                    image: getFileImageProvider(_logoPath),
                    fit: BoxFit.cover,
                  ),
          ),
          child: _logoPath.isEmpty
              ? Icon(
                  Icons.storefront_outlined,
                  size: 34,
                  color: scheme.onSurfaceVariant,
                )
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Logo', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                'Printed at the top of invoices and reports.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickLogo,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(_logoPath.isEmpty ? 'Choose' : 'Replace'),
                  ),
                  if (_logoPath.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        _logoPath = '';
                        _isDirty = true;
                      }),
                      child: const Text('Remove'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _group(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 12),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          for (final child in children)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
        ],
      ),
    );
  }

  Widget _field(
    String key, {
    bool required = false,
    int maxLines = 1,
    String? helper,
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: _fields[key],
      maxLines: maxLines,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: required ? '${_labels[key]} *' : _labels[key],
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
      validator:
          validator ??
          (required
              ? (value) => (value == null || value.trim().isEmpty)
                    ? '${_labels[key]} is required'
                    : null
              : null),
    );
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
    return ok ? null : 'Enter a valid email address';
  }
}
