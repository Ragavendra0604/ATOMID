import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:atomid/core/utils/image_provider_utils.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/domain/gst/gst_states.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

/// Business details printed on every invoice, receipt and report.
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
  // Unset until the owner chooses. Pre-selecting a state meant a shop that
  // saved this screen without touching it was silently registered in Tamil
  // Nadu — and every bill after that used it.
  String _selectedStateCode = '';
  String _selectedStateName = '';
  String _gstRegistrationStatus = 'Registered';
  bool _isDirty = false;

  static const _labels = {
    'name': 'Legal Business Name',
    'tradeName': 'Trade Name (Display / Brand)',
    'ownerName': 'Owner Name',
    'phone1': 'Primary Phone',
    'phone2': 'Secondary Phone',
    'email': 'Email',
    'website': 'Website',
    'gstNumber': 'GSTIN (15-character)',
    'panNumber': 'PAN Number',
    'address': 'Street Address',
    'city': 'City',
    'pincode': 'PIN Code',
    'country': 'Country',
    'invoicePrefix': 'Invoice Prefix',
    'financialYear': 'Financial Year',
  };

  @override
  void initState() {
    super.initState();
    final company = ref.read(companyProvider);
    _logoPath = company.logoPath;
    _gstRegistrationStatus = company.gstRegistrationStatus.isNotEmpty
        ? company.gstRegistrationStatus
        : 'Registered';

    final matchedState =
        GstStates.findByCode(company.stateCode) ??
        GstStates.findByName(company.state);

    _selectedStateCode = matchedState?.code ?? '';
    _selectedStateName = matchedState?.name ?? '';

    _fields = {
      'name': TextEditingController(text: company.name),
      'tradeName': TextEditingController(text: company.tradeName),
      'ownerName': TextEditingController(text: company.ownerName),
      'phone1': TextEditingController(text: company.phone1),
      'phone2': TextEditingController(text: company.phone2),
      'email': TextEditingController(text: company.email),
      'website': TextEditingController(text: company.website),
      'gstNumber': TextEditingController(text: company.gstNumber),
      'panNumber': TextEditingController(text: company.panNumber),
      'address': TextEditingController(text: company.address),
      'city': TextEditingController(text: company.city),
      'pincode': TextEditingController(text: company.pincode),
      'country': TextEditingController(
        text: company.country.isNotEmpty ? company.country : 'India',
      ),
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
      tradeName: _value('tradeName'),
      logoPath: _logoPath,
      ownerName: _value('ownerName'),
      gstNumber: _value('gstNumber').toUpperCase(),
      gstRegistrationStatus: _gstRegistrationStatus,
      panNumber: _value('panNumber').toUpperCase(),
      phone1: _value('phone1'),
      phone2: _value('phone2'),
      email: _value('email'),
      website: _value('website'),
      address: _value('address'),
      city: _value('city'),
      state: _selectedStateName,
      stateCode: _selectedStateCode,
      country: _value('country').isEmpty ? 'India' : _value('country'),
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
    final gstin = _value('gstNumber').toUpperCase();
    final isValidGstin = GstStates.isValidGstin(gstin);
    final isGstinEmpty = gstin.isEmpty;

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
                        _field(
                          'name',
                          required: true,
                          helper:
                              'Legal business name registered with tax authorities',
                        ),
                        _field(
                          'tradeName',
                          helper:
                              'Display name / Board name if different from legal name',
                        ),
                        _field('ownerName'),
                      ]),
                      _group('GST & Tax Registration', [
                        DropdownButtonFormField<String>(
                          initialValue: _gstRegistrationStatus,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'GST Registration Status',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Registered',
                              child: Text(
                                'Regular Registered (Tax Invoice)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Composition',
                              child: Text(
                                'Composition Scheme (Bill of Supply)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Unregistered',
                              child: Text(
                                'Unregistered',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _gstRegistrationStatus = val;
                                _isDirty = true;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        _field(
                          'gstNumber',
                          helper: isGstinEmpty
                              ? 'Enter 15-character GSTIN (e.g. 33AAAAA0000A1Z5)'
                              : null,
                          validator: (val) {
                            if (_gstRegistrationStatus == 'Registered' &&
                                (val == null || val.trim().isEmpty)) {
                              return 'GSTIN is required for registered business';
                            }
                            if (val != null &&
                                val.trim().isNotEmpty &&
                                !GstStates.isValidGstin(val.trim())) {
                              return 'Invalid GSTIN format (must be 15 characters, starting with 2-digit state code)';
                            }
                            return null;
                          },
                        ),
                        if (!isGstinEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            child: Row(
                              children: [
                                Icon(
                                  isValidGstin
                                      ? Icons.check_circle
                                      : Icons.error_outline,
                                  size: 16,
                                  color: isValidGstin
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isValidGstin
                                      ? 'GSTIN format valid'
                                      : 'GSTIN format incomplete',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isValidGstin
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        _field('panNumber', helper: '10-character PAN number'),
                      ]),
                      _group('Contact Details', [
                        _field('phone1', keyboard: TextInputType.phone),
                        _field('phone2', keyboard: TextInputType.phone),
                        _field(
                          'email',
                          keyboard: TextInputType.emailAddress,
                          validator: _validateEmail,
                        ),
                        _field('website'),
                      ]),
                      _group('Shop Address & Place of Business', [
                        _field('address', maxLines: 2),
                        Row(
                          children: [
                            Expanded(child: _field('city')),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedStateCode,
                                decoration: const InputDecoration(
                                  labelText: 'State / UT (Shop) *',
                                  border: OutlineInputBorder(),
                                  helperText: 'Required before billing',
                                ),
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('Select state'),
                                  ),
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
                                // GST cannot be calculated without it, so the
                                // form refuses to save rather than letting a
                                // shop bill from nowhere.
                                validator: (value) =>
                                    (value == null || value.isEmpty)
                                    ? 'Select your shop state'
                                    : null,
                                onChanged: (val) {
                                  final found = val == null || val.isEmpty
                                      ? null
                                      : GstStates.findByCode(val);
                                  setState(() {
                                    _selectedStateCode = found?.code ?? '';
                                    _selectedStateName = found?.name ?? '';
                                    _isDirty = true;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
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
                      _group('Documents & Invoicing', [
                        _field(
                          'invoicePrefix',
                          helper:
                              'Invoices are numbered PREFIX-YYYYMMDD-DEVICE-0001',
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
    final theme = Theme.of(context);
    final hasLogo = _logoPath.isNotEmpty;

    return Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 54,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            backgroundImage: hasLogo ? getFileImageProvider(_logoPath) : null,
            child: hasLogo
                ? null
                : Icon(
                    Icons.storefront_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: IconButton.filled(
              onPressed: _pickLogo,
              icon: const Icon(Icons.photo_camera, size: 20),
              tooltip: 'Change logo',
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _field(
    String key, {
    bool required = false,
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    String? helper,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: _fields[key],
      keyboardType: keyboard,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: _labels[key] ?? key,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
      validator:
          validator ??
          (val) {
            if (required && (val == null || val.trim().isEmpty)) {
              return '${_labels[key]} is required';
            }
            return null;
          },
    );
  }

  String? _validateEmail(String? val) {
    if (val == null || val.trim().isEmpty) return null;
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(val.trim())) return 'Enter a valid email address';
    return null;
  }
}
