import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/core/services/rbac_service.dart';
import 'package:atomid/data/models/permission_model.dart';

class RoleGuard extends ConsumerWidget {
  final Widget child;
  final Widget fallback;
  final Permission? requiredPermission;
  final bool ownerOnly;

  const RoleGuard({
    super.key,
    required this.child,
    this.fallback = const SizedBox.shrink(),
    this.requiredPermission,
    this.ownerOnly = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentEmployee = ref.watch(currentEmployeeProvider);

    if (currentEmployee == null) {
      return fallback;
    }

    if (ownerOnly) {
      if (RbacService.isOwner(currentEmployee)) {
        return child;
      } else {
        return fallback;
      }
    }

    if (requiredPermission != null) {
      if (RbacService.hasPermission(currentEmployee, requiredPermission!)) {
        return child;
      } else {
        return fallback;
      }
    }

    return child;
  }
}
