# TVS Electronics LP 46 DLITE Architecture Guide

This document outlines the architecture for printing 2-column continuous roll price tags on the TVS Electronics LP 46 DLITE.

## 1. Hardware & Media Geometry
- **Printer**: TVS Electronics LP 46 DLITE
- **Media**: Continuous Roll, Die-Cut Labels
- **Columns**: 2
- **Individual Label Size**: 50 mm × 35 mm
- **Sensor Mode**: Gap

## 2. Print Workflow Overview
1. **User Interface**: `bulk_generator_screen.dart` calculates rows based on `ceil(quantity / columns)`.
2. **Layout Engine**: `label_layout_engine.dart` uses `continuousPageFormat` to dynamically calculate the total height required for the roll: `topMargin + (rows * labelHeight) + ((rows - 1) * verticalGap) + bottomMargin`.
3. **PDF Generator**: `export_service.dart` renders exactly **ONE dynamic PDF page**. It does NOT generate artificial empty labels for odd quantities.
4. **Renderer**: `label_renderer.dart` restricts content to exactly 50×35 mm to prevent clipping, allocating fixed percentage heights to Product Name (50%), Barcode (30%), and Price (20%).

## 3. A4 vs. Continuous Roll Isolation
The application maintains two strictly isolated pipelines:
- **A4 Sheets**: Uses Legacy fixed-height `pdfPageFormat` and iterates multiple pages via `calculateTotalPages`.
- **LP46 Continuous**: Uses `LabelPageModel.continuousRoll` to generate a single document. The UI displays "1 continuous print page" instead of sheet calculations.

## 4. Physical Gap Sensing & Responsibility
### Software Responsibility
The Atom ID application is strictly responsible for generating accurate page geometry. It calculates a single long image containing the required grid of labels.

### Hardware Responsibility
The application **does not** detect physical gaps or issue manual form-feed commands. Media sensing, gap detection, and physical roll advancement are the exclusive responsibilities of the TVS LP 46 hardware and the installed Windows printer driver. The printer must be calibrated locally to the physical stock to properly map the continuous image stream onto the physical die-cut gaps.

## 5. Failure Handling & Transactions
Printing is a downstream operation independent of sales logic. If the LP46 printer is offline or the spooler rejects the job:
- The transaction succeeds.
- Inventory is updated.
- A clean application-level error is displayed to the user via `PrintJobManager`.
- The user can retry printing manually.

## 6. Physical Validation Checklist
When validating the implementation on the actual hardware, ensure:
- [ ] Both columns print successfully.
- [ ] Labels align perfectly within the physical 50×35 mm die-cut boundaries.
- [ ] No text is clipped or scaled down unexpectedly.
- [ ] Odd quantities leave the bottom-right slot empty.
- [ ] Successive rows do not vertically drift across the physical gaps. (If drifting occurs, hardware driver calibration is required).
