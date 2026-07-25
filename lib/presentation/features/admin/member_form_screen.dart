import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/data/models/employee_model.dart';
import 'package:atomid/data/models/role_model.dart';
import 'package:atomid/data/models/permission_model.dart';

class MemberFormScreen extends ConsumerStatefulWidget {
  final EmployeeModel? employee;

  const MemberFormScreen({super.key, this.employee});

  @override
  ConsumerState<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends ConsumerState<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _pinCtrl;
  
  Role _selectedRole = Role.cashier;
  bool _isActive = true;
  List<Permission> _selectedPermissions = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.employee?.fullName ?? '');
    _emailCtrl = TextEditingController(text: widget.employee?.email ?? '');
    _phoneCtrl = TextEditingController(text: widget.employee?.phoneNumber ?? '');
    _pinCtrl = TextEditingController(text: widget.employee?.pin ?? '');
    _selectedRole = widget.employee?.role ?? Role.cashier;
    _isActive = widget.employee?.isActive ?? true;
    _selectedPermissions = widget.employee?.permissions.toList() ?? [];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _save() async {
    if (_formKey.currentState!.validate()) {
      final repo = ref.read(storageRepositoryProvider);
      final currentEmployee = ref.read(currentEmployeeProvider);
      
      final newEmployee = EmployeeModel(
        id: widget.employee?.id,
        fullName: _nameCtrl.text,
        email: _emailCtrl.text,
        phoneNumber: _phoneCtrl.text,
        role: _selectedRole,
        permissions: _selectedPermissions,
        pin: _pinCtrl.text.isEmpty ? null : _pinCtrl.text,
        isActive: _isActive,
        isDeleted: widget.employee?.isDeleted ?? false,
      );

      await repo.saveEmployee(newEmployee, actionBy: currentEmployee?.id ?? 'owner');
      if (mounted && context.mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.employee == null ? 'Create Member' : 'Edit Member'),
        actions: [
          if (widget.employee != null && !widget.employee!.isDeleted)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete Member?'),
                    content: const Text('This will soft-delete the member.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                    ],
                  )
                );
                if (confirm == true) {
                  final repo = ref.read(storageRepositoryProvider);
                  final currentEmployee = ref.read(currentEmployeeProvider);
                  await repo.deleteEmployee(widget.employee!.id, actionBy: currentEmployee?.id ?? 'owner');
                  if (mounted && context.mounted) {
                    Navigator.pop(context);
                  }
                }
              },
            )
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name'),
              validator: (val) => val == null || val.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Email Address'),
              validator: (val) => val == null || val.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone Number'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pinCtrl,
              decoration: const InputDecoration(labelText: 'POS PIN (Optional)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Role>(
              initialValue: _selectedRole,
              decoration: const InputDecoration(labelText: 'Role'),
              items: Role.values.map((r) => DropdownMenuItem(value: r, child: Text(r.name))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedRole = val);
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Is Active'),
              value: _isActive,
              onChanged: (val) => setState(() => _isActive = val),
            ),
            const Divider(),
            Text('Permissions', style: Theme.of(context).textTheme.titleMedium),
            ...Permission.values.map((p) => CheckboxListTile(
              title: Text(p.name),
              value: _selectedPermissions.contains(p),
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedPermissions.add(p);
                  } else {
                    _selectedPermissions.remove(p);
                  }
                });
              },
            )),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _save,
              child: const Text('Save Member'),
            ),
          ],
        ),
      ),
    );
  }
}
