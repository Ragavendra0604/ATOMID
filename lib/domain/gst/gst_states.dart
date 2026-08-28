/// Master list of Indian States and Union Territories with official 2-digit GST codes,
/// UTGST levy classification, and structural GSTIN validation according to CBIC rules.
class GstState {
  final String code; // 2-digit string, e.g. "33", "29", "07"
  final String name;
  final bool isUnionTerritoryWithoutLegislature;

  const GstState({
    required this.code,
    required this.name,
    this.isUnionTerritoryWithoutLegislature = false,
  });

  @override
  String toString() => '$code - $name';
}

/// Centralized state / UT levy master for Indian GST.
class GstStates {
  const GstStates._();

  /// 36 official GST state/UT jurisdictions with their 2-digit codes.
  ///
  /// Union Territories WITHOUT state legislature enact the UTGST Act 2017:
  /// - Andaman and Nicobar Islands (35)
  /// - Chandigarh (04)
  /// - Dadra and Nagar Haveli and Daman and Diu (26)
  /// - Ladakh (38)
  /// - Lakshadweep (31)
  /// - Other Territory (97)
  ///
  /// Delhi (07), Puducherry (34), and Jammu & Kashmir (01) have their own legislatures
  /// and have enacted SGST Acts, so SGST applies.
  static const List<GstState> all = [
    GstState(code: '01', name: 'Jammu and Kashmir'),
    GstState(code: '02', name: 'Himachal Pradesh'),
    GstState(code: '03', name: 'Punjab'),
    GstState(
      code: '04',
      name: 'Chandigarh',
      isUnionTerritoryWithoutLegislature: true,
    ),
    GstState(code: '05', name: 'Uttarakhand'),
    GstState(code: '06', name: 'Haryana'),
    GstState(code: '07', name: 'Delhi'),
    GstState(code: '08', name: 'Rajasthan'),
    GstState(code: '09', name: 'Uttar Pradesh'),
    GstState(code: '10', name: 'Bihar'),
    GstState(code: '11', name: 'Sikkim'),
    GstState(code: '12', name: 'Arunachal Pradesh'),
    GstState(code: '13', name: 'Nagaland'),
    GstState(code: '14', name: 'Manipur'),
    GstState(code: '15', name: 'Mizoram'),
    GstState(code: '16', name: 'Tripura'),
    GstState(code: '17', name: 'Meghalaya'),
    GstState(code: '18', name: 'Assam'),
    GstState(code: '19', name: 'West Bengal'),
    GstState(code: '20', name: 'Jharkhand'),
    GstState(code: '21', name: 'Odisha'),
    GstState(code: '22', name: 'Chhattisgarh'),
    GstState(code: '23', name: 'Madhya Pradesh'),
    GstState(code: '24', name: 'Gujarat'),
    GstState(
      code: '26',
      name: 'Dadra and Nagar Haveli and Daman and Diu',
      isUnionTerritoryWithoutLegislature: true,
    ),
    GstState(code: '27', name: 'Maharashtra'),
    GstState(code: '29', name: 'Karnataka'),
    GstState(code: '30', name: 'Goa'),
    GstState(
      code: '31',
      name: 'Lakshadweep',
      isUnionTerritoryWithoutLegislature: true,
    ),
    GstState(code: '32', name: 'Kerala'),
    GstState(code: '33', name: 'Tamil Nadu'),
    GstState(code: '34', name: 'Puducherry'),
    GstState(
      code: '35',
      name: 'Andaman and Nicobar Islands',
      isUnionTerritoryWithoutLegislature: true,
    ),
    GstState(code: '36', name: 'Telangana'),
    GstState(code: '37', name: 'Andhra Pradesh'),
    GstState(
      code: '38',
      name: 'Ladakh',
      isUnionTerritoryWithoutLegislature: true,
    ),
    GstState(
      code: '97',
      name: 'Other Territory',
      isUnionTerritoryWithoutLegislature: true,
    ),
  ];

  static final Map<String, GstState> _byCode = {for (final s in all) s.code: s};

  static final Map<String, GstState> _byNormalizedName = {
    for (final s in all) _normalize(s.name): s,
  };

  static String _normalize(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Finds a state by its 2-digit GST code (e.g. "33").
  static GstState? findByCode(String? code) {
    if (code == null || code.trim().isEmpty) return null;
    final clean = code.trim().padLeft(2, '0');
    return _byCode[clean];
  }

  /// Finds a state by name (case- and punctuation-insensitive).
  static GstState? findByName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final direct = _byNormalizedName[_normalize(name)];
    if (direct != null) return direct;

    // Handle common aliases
    final norm = _normalize(name);
    if (norm == 'andhra' || norm == 'ap') {
      return findByCode('37');
    }
    if (norm == 'tamilnadu' || norm == 'tn') {
      return findByCode('33');
    }
    if (norm == 'karnataka' || norm == 'ka') {
      return findByCode('29');
    }
    if (norm == 'kerala' || norm == 'kl') {
      return findByCode('32');
    }
    if (norm == 'maharashtra' || norm == 'mh') {
      return findByCode('27');
    }
    if (norm == 'telangana' || norm == 'ts' || norm == 'tg') {
      return findByCode('36');
    }
    if (norm == 'delhi' || norm == 'nctdelhi' || norm == 'dl') {
      return findByCode('07');
    }
    if (norm == 'pondicherry') {
      return findByCode('34');
    }
    if (norm == 'orissa') {
      return findByCode('21');
    }
    if (norm == 'uttaranchal') {
      return findByCode('05');
    }
    if (norm == 'dnh' || norm == 'daman' || norm == 'diu' || norm == 'dnhdd') {
      return findByCode('26');
    }
    return null;
  }

  /// Validates a GSTIN structurally according to the 15-character standard:
  /// `^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$`
  ///
  /// Also checks that the first 2 digits match a valid state code and optionally
  /// match [expectedStateCode] if provided.
  static GstinValidationResult validateGstin(
    String? gstin, {
    String? expectedStateCode,
  }) {
    if (gstin == null || gstin.trim().isEmpty) {
      return const GstinValidationResult(
        status: GstinStatus.empty,
        message: 'No GSTIN entered.',
      );
    }

    final trimmed = gstin.trim().toUpperCase();

    if (trimmed.length != 15) {
      return GstinValidationResult(
        status: GstinStatus.invalidFormat,
        message:
            'GSTIN must be exactly 15 characters (currently ${trimmed.length}).',
      );
    }

    final gstRegex = RegExp(
      r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$',
    );
    if (!gstRegex.hasMatch(trimmed)) {
      return const GstinValidationResult(
        status: GstinStatus.invalidFormat,
        message: 'Invalid GSTIN structure (Format: 22AAAAA0000A1Z5).',
      );
    }

    final statePrefix = trimmed.substring(0, 2);
    final state = findByCode(statePrefix);
    if (state == null) {
      return GstinValidationResult(
        status: GstinStatus.invalidStateCode,
        message: 'Unknown state code "$statePrefix" in GSTIN.',
      );
    }

    if (expectedStateCode != null && expectedStateCode.trim().isNotEmpty) {
      final exp = expectedStateCode.trim().padLeft(2, '0');
      if (exp != statePrefix) {
        final expectedState = findByCode(exp);
        return GstinValidationResult(
          status: GstinStatus.stateMismatch,
          stateCode: statePrefix,
          stateName: state.name,
          message:
              'GSTIN state prefix ($statePrefix - ${state.name}) does not match selected state ($exp - ${expectedState?.name ?? exp}).',
        );
      }
    }

    return GstinValidationResult(
      status: GstinStatus.valid,
      stateCode: statePrefix,
      stateName: state.name,
      pan: trimmed.substring(2, 12),
      message: 'GSTIN format valid (${state.name}).',
    );
  }

  /// Resolves the GST state of a party from what its record actually holds.
  ///
  /// The order is deliberate: a state someone typed always wins, and the GSTIN
  /// is read only when no state was recorded. Reading the GSTIN is not
  /// inference — the first two digits *are* the registration's state code —
  /// which is why nothing else about the party (name, address, city, phone,
  /// pincode) is ever consulted.
  ///
  /// Shared by the sale and purchase paths so a customer's GSTIN and a
  /// supplier's are held to one standard.
  static PartyStateResolution resolvePartyState({
    required String label,
    String? stateCode,
    String? stateName,
    String? gstin,
  }) {
    final trimmedGstin = (gstin ?? '').trim();

    final statedState =
        findByCode(stateCode) ??
        (stateName != null && stateName.trim().isNotEmpty
            ? findByName(stateName)
            : null);

    if (trimmedGstin.isEmpty) {
      return statedState != null
          ? PartyStateResolution._(state: statedState, basis: '$label state')
          : PartyStateResolution._(
              error:
                  '$label state is not set. Record the state, or a GSTIN it '
                  'can be read from, before calculating tax.',
            );
    }

    final check = validateGstin(
      trimmedGstin,
      expectedStateCode: statedState?.code,
    );

    switch (check.status) {
      case GstinStatus.stateMismatch:
        return PartyStateResolution._(
          error:
              '$label GSTIN and $label state do not agree. ${check.message} '
              'Correct one of them before calculating tax.',
        );
      case GstinStatus.valid:
        final fromGstin = findByCode(check.stateCode);
        if (statedState != null) {
          return PartyStateResolution._(
            state: statedState,
            basis: '$label state (confirmed by GSTIN)',
          );
        }
        return PartyStateResolution._(
          state: fromGstin,
          basis: '$label GSTIN state prefix',
          derivedFromGstin: true,
        );
      case GstinStatus.empty:
      case GstinStatus.invalidFormat:
      case GstinStatus.invalidStateCode:
        // Nothing is ever derived from a GSTIN that does not parse.
        if (statedState != null) {
          return PartyStateResolution._(
            state: statedState,
            basis: '$label state',
          );
        }
        return PartyStateResolution._(
          error:
              '$label GSTIN "$trimmedGstin" is not a valid GSTIN, so the state '
              'could not be read from it. Correct the GSTIN or set the '
              '$label state.',
        );
    }
  }

  /// Convenience alias for [all].
  static List<GstState> get allStates => all;

  /// Returns true if the state code belongs to a UT without state legislature (UTGST jurisdiction).
  static bool isUtgstState(String? stateCode) {
    if (stateCode == null || stateCode.trim().isEmpty) return false;
    final state = findByCode(stateCode);
    return state?.isUnionTerritoryWithoutLegislature ?? false;
  }

  /// Returns true if the GSTIN matches the standard structural format and has a valid state prefix.
  static bool isValidGstin(String? gstin, {String? expectedStateCode}) {
    return validateGstin(gstin, expectedStateCode: expectedStateCode).isValid;
  }

  /// Extracts the 2-digit state prefix code from a valid GSTIN.
  static String? extractStateCode(String? gstin) {
    final res = validateGstin(gstin);
    return res.isValid ? res.stateCode : null;
  }
}

enum GstinStatus {
  empty,
  valid,
  invalidFormat,
  invalidStateCode,
  stateMismatch,
}

class GstinValidationResult {
  final GstinStatus status;
  final String? stateCode;
  final String? stateName;
  final String? pan;
  final String message;

  const GstinValidationResult({
    required this.status,
    this.stateCode,
    this.stateName,
    this.pan,
    required this.message,
  });

  bool get isValid => status == GstinStatus.valid;
}

/// The outcome of [GstStates.resolvePartyState].
class PartyStateResolution {
  const PartyStateResolution._({
    this.state,
    this.basis = '',
    this.error,
    this.derivedFromGstin = false,
  });

  final GstState? state;

  /// Where the state came from, for the audit trail on a document.
  final String basis;

  /// Set when the state could not be established safely. Never both this and
  /// [state]: the caller blocks rather than guessing.
  final String? error;

  final bool derivedFromGstin;

  bool get isResolved => state != null && error == null;
}
