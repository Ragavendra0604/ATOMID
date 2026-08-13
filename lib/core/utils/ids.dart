import 'package:uuid/uuid.dart';

/// Identifier generation.
///
/// Everything that becomes a Hive key or a Firestore document id comes from
/// here. Millisecond timestamps were previously used as keys, which silently
/// overwrote records created in the same millisecond (two ledger entries from
/// one sale, several stock movements from one checkout).
class Ids {
  const Ids._();

  static const Uuid _uuid = Uuid();

  static String generate() => _uuid.v4();

  /// Short, human-quotable suffix used to keep offline document numbers
  /// distinct between devices.
  static String shortCode(String deviceId) {
    final cleaned = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (cleaned.length <= 4) return cleaned.toUpperCase().padLeft(4, '0');
    return cleaned.substring(cleaned.length - 4).toUpperCase();
  }
}
