import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/domain/gst/gst_models.dart';
import 'package:atomid/domain/gst/gst_rate_resolver.dart';
import 'package:atomid/domain/gst/gst_states.dart';
import 'package:atomid/domain/gst/gst_treatment.dart';

/// Central statutory GST engine for AtomID Store.
///
/// This is the SINGLE AUTHORITY for all GST mathematics in the application.
/// Checkout, invoice printing, thermal receipts, supplier purchases, and GST
/// reports all derive from this calculation.
class Gst {
  const Gst._();

  /// Computes the complete GST breakdown for a transaction.
  ///
  /// Returns a valid [GstCalculationResult] when inputs are sound, or an invalid
  /// result with actionable errors if tax cannot be safely determined.
  static GstCalculationResult compute(GstCalculationInput input) {
    final errors = <String>[];

    if (input.lines.isEmpty) {
      errors.add('Add at least one item to calculate GST.');
      return GstCalculationResult.invalid(errors);
    }

    // 1. Resolve Seller State
    final sellerGstState =
        GstStates.findByCode(input.sellerStateCode) ??
        GstStates.findByName(input.sellerState);

    if (sellerGstState == null) {
      errors.add(
        input.sellerState.trim().isEmpty && input.sellerStateCode.trim().isEmpty
            ? 'Configure your shop state before billing. '
                  'Settings > Business Details.'
            : 'Shop state is not configured or unknown '
                  '("${input.sellerState}"). '
                  'Configure your shop state in Settings > Business Details.',
      );
    }

    // 1b. Customer GSTIN.
    //
    // The first two digits of a GSTIN ARE the registration's state code, so
    // reading them is not inference from address text, city or pincode — it is
    // reading the number. A structurally invalid GSTIN yields nothing.
    final customerGstin = (input.customerGstin ?? '').trim();
    String? gstinStateCode;
    var customerGstinMalformed = false;

    if (customerGstin.isNotEmpty) {
      // The state the customer record states, however it was recorded — a
      // code, or a name the master resolves to one. A name that disagrees
      // with the GSTIN is the same defect as a code that does.
      final statedCustomerCode =
          (input.customerStateCode != null &&
              input.customerStateCode!.trim().isNotEmpty)
          ? input.customerStateCode
          : GstStates.findByName(input.customerState)?.code;

      final gstinCheck = GstStates.validateGstin(
        customerGstin,
        expectedStateCode: statedCustomerCode,
      );

      if (gstinCheck.status == GstinStatus.valid) {
        gstinStateCode = gstinCheck.stateCode;
      } else if (gstinCheck.status == GstinStatus.stateMismatch) {
        // Never silently pick a side: the cashier is told which two values
        // disagree and has to correct one of them.
        errors.add(
          'Customer GSTIN and customer state do not agree. '
          '${gstinCheck.message} '
          'Correct the customer record before billing.',
        );
      } else if (gstinCheck.status == GstinStatus.invalidFormat ||
          gstinCheck.status == GstinStatus.invalidStateCode) {
        customerGstinMalformed = true;
      }
    }

    // 2. Resolve Place of Supply (POS)
    String? resolvedPosCode;
    String? resolvedPosState;
    String resolvedPosBasis = '';

    // Check explicit destination
    if (input.destinationStateCode != null &&
        input.destinationStateCode!.trim().isNotEmpty) {
      final destState = GstStates.findByCode(input.destinationStateCode);
      if (destState != null) {
        resolvedPosCode = destState.code;
        resolvedPosState = destState.name;
        resolvedPosBasis = 'Destination / Delivery Address';
      }
    }

    // Check customer state
    if (resolvedPosCode == null &&
        input.customerStateCode != null &&
        input.customerStateCode!.trim().isNotEmpty) {
      final custState = GstStates.findByCode(input.customerStateCode);
      if (custState != null) {
        resolvedPosCode = custState.code;
        resolvedPosState = custState.name;
        resolvedPosBasis = 'Customer Billing State';
      }
    }

    if (resolvedPosCode == null &&
        input.customerState != null &&
        input.customerState!.trim().isNotEmpty) {
      final custState = GstStates.findByName(input.customerState);
      if (custState != null) {
        resolvedPosCode = custState.code;
        resolvedPosState = custState.name;
        resolvedPosBasis = 'Customer Billing State';
      }
    }

    // Derived from the customer's own GSTIN when no state was recorded.
    // This runs after the explicit fields so a stated state always wins.
    if (resolvedPosCode == null && gstinStateCode != null) {
      final gstinState = GstStates.findByCode(gstinStateCode);
      if (gstinState != null) {
        resolvedPosCode = gstinState.code;
        resolvedPosState = gstinState.name;
        resolvedPosBasis = 'Customer GSTIN State Prefix';
      }
    }

    // Handle Walk-in counter sale according to shop policy
    if (resolvedPosCode == null) {
      if (input.isWalkIn) {
        final policy = input.walkInPosPolicy.toUpperCase();
        if (policy == 'USE_SHOP_STATE' || policy == 'ASK_ONLY_WHEN_REQUIRED') {
          if (sellerGstState != null) {
            resolvedPosCode = sellerGstState.code;
            resolvedPosState = sellerGstState.name;
            resolvedPosBasis =
                'Over-the-counter counter sale (Shop State Policy)';
          }
        } else if (policy == 'REQUIRE_STATE') {
          errors.add(
            'Place of Supply state is required by shop policy. Select customer state.',
          );
        } else if (policy == 'ASK_AT_CHECKOUT') {
          errors.add('Place of Supply must be confirmed at checkout.');
        } else {
          // Default to shop state for physical retail over-the-counter
          if (sellerGstState != null) {
            resolvedPosCode = sellerGstState.code;
            resolvedPosState = sellerGstState.name;
            resolvedPosBasis = 'Over-the-counter counter sale';
          }
        }
      } else if (customerGstinMalformed) {
        errors.add(
          'Customer GSTIN "$customerGstin" is not a valid GSTIN, so the '
          'Place of Supply could not be determined from it. Correct the GSTIN '
          'or set the customer state.',
        );
      } else {
        errors.add('Place of Supply is required for this transaction.');
      }
    }

    // Determine Intra-State vs Inter-State & UTGST
    final bool isInterState =
        sellerGstState != null &&
        resolvedPosCode != null &&
        sellerGstState.code != resolvedPosCode;

    final bool isUtgst =
        !isInterState &&
        sellerGstState != null &&
        sellerGstState.isUnionTerritoryWithoutLegislature;

    // 3. Resolve GST Rates & Validate Lines
    final lineResolutions = <GstRateResolution>[];
    for (int i = 0; i < input.lines.length; i++) {
      final line = input.lines[i];
      final resolution = GstRateResolver.resolve(
        gstTreatment: line.gstTreatment,
        configuredRate: line.gstRate,
        cessRate: line.cessRate,
        rateConfigId: line.gstRateConfigId,
        transactionDate: input.transactionDate,
      );

      lineResolutions.add(resolution);

      if (!resolution.isResolved) {
        errors.add(
          '${line.productName} (${line.variantSize}): ${resolution.errorMessage}',
        );
      }
    }

    if (errors.isNotEmpty) {
      return GstCalculationResult.invalid(errors);
    }

    // 4. Calculate Subtotal and Allocate Document Discount
    final lineGrossValues = [
      for (final line in input.lines) Fmt.round2(line.lineGross),
    ];
    final subtotal = Fmt.round2(lineGrossValues.fold(0.0, (sum, g) => sum + g));

    // Per-line discounts, taken off before the document discount is spread.
    //
    // [GstLineInput.lineDiscount] has always been part of the input and was
    // simply never read; a sale has never set it, so every existing figure is
    // unchanged. A purchase does set it — a supplier's invoice discounts
    // individual lines rather than the bill — and it must not be redistributed
    // across the other lines the way a document discount is.
    final lineDiscounts = [
      for (var i = 0; i < input.lines.length; i++)
        Fmt.round2(input.lines[i].lineDiscount.clamp(0.0, lineGrossValues[i])),
    ];
    final totalLineDiscount = Fmt.round2(
      lineDiscounts.fold(0.0, (sum, d) => sum + d),
    );

    // Manual discount
    double manualDiscount = 0.0;
    double appliedPercent = 0.0;
    final headroomAfterReward = Fmt.round2(
      subtotal - input.rewardDiscountAmount,
    );

    if (input.requestedDiscountPercent > 0) {
      appliedPercent = Fmt.round2(
        input.requestedDiscountPercent.clamp(0.0, 100.0),
      );
      final requestedAmount = Fmt.round2(subtotal * appliedPercent / 100.0);
      manualDiscount = Fmt.round2(
        requestedAmount.clamp(
          0.0,
          headroomAfterReward < 0 ? 0.0 : headroomAfterReward,
        ),
      );
      if (manualDiscount < requestedAmount) {
        appliedPercent = subtotal > 0
            ? Fmt.round2(manualDiscount / subtotal * 100.0)
            : 0.0;
      }
    } else if (input.manualDiscountAmount > 0) {
      manualDiscount = Fmt.round2(
        input.manualDiscountAmount.clamp(
          0.0,
          headroomAfterReward < 0 ? 0.0 : headroomAfterReward,
        ),
      );
      appliedPercent = subtotal > 0
          ? Fmt.round2(manualDiscount / subtotal * 100.0)
          : 0.0;
    }

    final totalDiscountToAllocate = Fmt.round2(
      (input.rewardDiscountAmount + manualDiscount).clamp(0.0, subtotal),
    );

    // Proportional discount allocation across lines
    final allocatedDiscounts = <double>[];
    if (subtotal <= 0 || totalDiscountToAllocate <= 0) {
      for (int i = 0; i < input.lines.length; i++) {
        allocatedDiscounts.add(0.0);
      }
    } else {
      double runningAllocated = 0.0;
      int largestLineIndex = 0;
      double largestGross = -1.0;

      for (int i = 0; i < input.lines.length; i++) {
        final gross = lineGrossValues[i];
        if (gross > largestGross) {
          largestGross = gross;
          largestLineIndex = i;
        }

        final lineShare = Fmt.round2(
          totalDiscountToAllocate * (gross / subtotal),
        );
        allocatedDiscounts.add(lineShare);
        runningAllocated = Fmt.round2(runningAllocated + lineShare);
      }

      // Reconcile residual rounding differences onto the largest line
      final diff = Fmt.round2(totalDiscountToAllocate - runningAllocated);
      if (diff.abs() > 0.0001 && largestLineIndex < allocatedDiscounts.length) {
        allocatedDiscounts[largestLineIndex] = Fmt.round2(
          allocatedDiscounts[largestLineIndex] + diff,
        );
      }
    }

    // 5. Compute Line-Level Taxes
    final calculatedLines = <GstLineResult>[];

    double runningTaxable = 0.0;
    double runningCgst = 0.0;
    double runningSgst = 0.0;
    double runningUtgst = 0.0;
    double runningIgst = 0.0;
    double runningCess = 0.0;
    double runningPreRoundTotal = 0.0;

    for (int i = 0; i < input.lines.length; i++) {
      final line = input.lines[i];
      final res = lineResolutions[i];
      final lineGross = lineGrossValues[i];
      final discount = Fmt.round2(lineDiscounts[i] + allocatedDiscounts[i]);
      final netGross = Fmt.round2(
        (lineGross - discount).clamp(0.0, double.infinity),
      );

      final rate = res.rate;
      final cessRate = res.cessRate;
      final totalRate = rate + cessRate;

      double taxableValue;
      double cgstRate = 0.0;
      double cgstAmount = 0.0;
      double sgstRate = 0.0;
      double sgstAmount = 0.0;
      double utgstRate = 0.0;
      double utgstAmount = 0.0;
      double igstRate = 0.0;
      double igstAmount = 0.0;
      double cessAmount = 0.0;
      double lineTotal;

      if (!GstTreatment.attractsTax(res.gstTreatment) || totalRate <= 0) {
        taxableValue = netGross;
        lineTotal = netGross;
      } else if (input.isInclusive && input.isInclusiveTaxFromRate) {
        // INCLUSIVE PRICING, tax derived from the rate. Every tax figure is
        // rate x taxable, so the GST shown on the invoice always reconciles
        // against the taxable value. The cost is that the line total can land
        // a paisa above the marked price — and that total is what the
        // customer pays. The shop chooses which of the two it wants; neither
        // has been confirmed as the legally required reading.
        taxableValue = Fmt.round2(netGross / (1.0 + (totalRate / 100.0)));
        final totalGst = Fmt.round2(taxableValue * (rate / 100.0));
        cessAmount = cessRate > 0
            ? Fmt.round2(taxableValue * (cessRate / 100.0))
            : 0.0;

        if (isInterState) {
          igstRate = rate;
          igstAmount = totalGst;
        } else {
          cgstRate = rate / 2.0;
          cgstAmount = Fmt.round2(totalGst / 2.0);
          if (isUtgst) {
            utgstRate = rate / 2.0;
            utgstAmount = Fmt.round2(totalGst - cgstAmount);
          } else {
            sgstRate = rate / 2.0;
            sgstAmount = Fmt.round2(totalGst - cgstAmount);
          }
        }
        lineTotal = Fmt.round2(
          taxableValue +
              cgstAmount +
              sgstAmount +
              utgstAmount +
              igstAmount +
              cessAmount,
        );
      } else if (input.isInclusive) {
        // INCLUSIVE PRICING: Extract tax from gross
        // Taxable = NetGross / (1 + (Rate + Cess)/100)
        // The marked price is authoritative: whatever is left after the
        // taxable value is the tax, so the customer pays exactly the shelf
        // price and the GST shown can sit a paisa off rate x taxable.
        taxableValue = Fmt.round2(netGross / (1.0 + (totalRate / 100.0)));
        final totalTax = Fmt.round2(netGross - taxableValue);

        if (cessRate > 0) {
          final totalGst = Fmt.round2(totalTax * (rate / totalRate));
          cessAmount = Fmt.round2(totalTax - totalGst);

          if (isInterState) {
            igstRate = rate;
            igstAmount = totalGst;
          } else {
            cgstRate = rate / 2.0;
            cgstAmount = Fmt.round2(totalGst / 2.0);
            if (isUtgst) {
              utgstRate = rate / 2.0;
              utgstAmount = Fmt.round2(totalGst - cgstAmount);
            } else {
              sgstRate = rate / 2.0;
              sgstAmount = Fmt.round2(totalGst - cgstAmount);
            }
          }
        } else {
          cessAmount = 0.0;
          if (isInterState) {
            igstRate = rate;
            igstAmount = totalTax;
          } else {
            cgstRate = rate / 2.0;
            cgstAmount = Fmt.round2(totalTax / 2.0);
            if (isUtgst) {
              utgstRate = rate / 2.0;
              utgstAmount = Fmt.round2(totalTax - cgstAmount);
            } else {
              sgstRate = rate / 2.0;
              sgstAmount = Fmt.round2(totalTax - cgstAmount);
            }
          }
        }
        lineTotal = netGross;
      } else {
        // EXCLUSIVE PRICING: Calculate tax on taxable value and add on top
        taxableValue = netGross;
        final totalGst = Fmt.round2(taxableValue * (rate / 100.0));
        cessAmount = cessRate > 0
            ? Fmt.round2(taxableValue * (cessRate / 100.0))
            : 0.0;

        if (isInterState) {
          igstRate = rate;
          igstAmount = totalGst;
        } else {
          cgstRate = rate / 2.0;
          cgstAmount = Fmt.round2(totalGst / 2.0);
          if (isUtgst) {
            utgstRate = rate / 2.0;
            utgstAmount = Fmt.round2(totalGst - cgstAmount);
          } else {
            sgstRate = rate / 2.0;
            sgstAmount = Fmt.round2(totalGst - cgstAmount);
          }
        }
        lineTotal = Fmt.round2(
          taxableValue +
              cgstAmount +
              sgstAmount +
              utgstAmount +
              igstAmount +
              cessAmount,
        );
      }

      final totalLineTax = Fmt.round2(
        cgstAmount + sgstAmount + utgstAmount + igstAmount + cessAmount,
      );

      calculatedLines.add(
        GstLineResult(
          productId: line.productId,
          productName: line.productName,
          productCode: line.productCode,
          variantBarcode: line.variantBarcode,
          variantSize: line.variantSize,
          unitPrice: line.unitPrice,
          quantity: line.quantity,
          hsn: line.hsn,
          uqc: line.uqc,
          gstTreatment: res.gstTreatment,
          gstRate: res.rate,
          cessRate: res.cessRate,
          gstRateConfigId: res.configId,
          lineGross: lineGross,
          discountAllocated: discount,
          taxableValue: taxableValue,
          cgstRate: cgstRate,
          cgstAmount: cgstAmount,
          sgstRate: sgstRate,
          sgstAmount: sgstAmount,
          utgstRate: utgstRate,
          utgstAmount: utgstAmount,
          igstRate: igstRate,
          igstAmount: igstAmount,
          cessAmount: cessAmount,
          totalTax: totalLineTax,
          lineTotal: lineTotal,
        ),
      );

      runningTaxable = Fmt.round2(runningTaxable + taxableValue);
      runningCgst = Fmt.round2(runningCgst + cgstAmount);
      runningSgst = Fmt.round2(runningSgst + sgstAmount);
      runningUtgst = Fmt.round2(runningUtgst + utgstAmount);
      runningIgst = Fmt.round2(runningIgst + igstAmount);
      runningCess = Fmt.round2(runningCess + cessAmount);
      runningPreRoundTotal = Fmt.round2(runningPreRoundTotal + lineTotal);
    }

    final totalGst = Fmt.round2(
      runningCgst + runningSgst + runningUtgst + runningIgst,
    );
    final totalTax = Fmt.round2(totalGst + runningCess);

    // 6. Round-Off Calculation
    double payableAmount;
    double roundOff;

    if (input.roundOffEnabled) {
      payableAmount = Fmt.round2(runningPreRoundTotal.roundToDouble());
      roundOff = Fmt.round2(payableAmount - runningPreRoundTotal);
    } else {
      payableAmount = runningPreRoundTotal;
      roundOff = 0.0;
    }

    return GstCalculationResult(
      isValid: true,
      errors: const [],
      lines: calculatedLines,
      subtotal: subtotal,
      discountAmount: Fmt.round2(totalDiscountToAllocate + totalLineDiscount),
      rewardDiscount: input.rewardDiscountAmount,
      manualDiscount: manualDiscount,
      appliedDiscountPercent: appliedPercent,
      taxableAmount: runningTaxable,
      cgstAmount: runningCgst,
      sgstAmount: runningSgst,
      utgstAmount: runningUtgst,
      igstAmount: runningIgst,
      cessAmount: runningCess,
      totalGst: totalGst,
      totalTax: totalTax,
      preRoundTotal: runningPreRoundTotal,
      roundOff: roundOff,
      payableAmount: payableAmount < 0 ? 0.0 : payableAmount,
      pricingMode: input.pricingMode,
      isInterState: isInterState,
      isUtgst: isUtgst,
      placeOfSupplyCode: resolvedPosCode ?? '',
      placeOfSupplyState: resolvedPosState ?? '',
      placeOfSupplyBasis: resolvedPosBasis,
    );
  }
}
