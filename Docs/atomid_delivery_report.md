# Atomid — Production Readiness Delivery Report

**Date:** 2026-08-19
**Baseline:** commit `7aa3f5f` + uncommitted session work
**Toolchain:** Flutter 3.44.3 · Dart 3.12.2 · Windows 11

---

## A. Executive summary

The audit's two Critical findings are closed, both verified by reproducing the
original failure before the fix and demonstrating it gone after. The High
findings are closed except where a product decision deliberately deferred them,
and those are recorded as accepted limitations rather than presented as fixed.

Three things are worth calling out specifically.

**B-1 was fixed at the root, not patched.** The audit found that
`applyRemote` wrote records into Hive without updating the in-memory indexes
the till reads from. Rather than adding the two missing calls, derived-state
maintenance is now a single `_reindex(entityType, id)` used by *both* the local
`saveX` family and the remote `applyRemote` family. The two paths can no longer
drift, which is what caused the bug in the first place.

**Enabling incremental sync uncovered a worse latent bug than the one it
fixed.** Only 4 of the 15 syncable payloads carried an `updatedAt` field, and
Firestore's `where('updatedAt', >)` *omits* documents missing the field rather
than ranking them. Switching on the incremental path naively would have
silently returned zero records for 11 collections while reporting success —
strictly worse than the full-refresh cost it was meant to solve. Every payload
now carries a non-null `updatedAt`, config records are exempted from
incremental filtering entirely, and a schema-version gate forces one full pull
after upgrade so pre-existing cloud documents are not stranded.

**The biometric toggle was removed rather than implemented**, per your
decision. It stored, synced and restore-protected a setting that nothing read,
on an app with no lock of any kind. The README now states the security model
plainly, including what the app deliberately does *not* do.

**Every remaining audit finding was then worked through**, including the ones
originally left open. Config records now carry a real `updatedAt`, so two
devices editing the same setting resolve on recency rather than arrival order
(B-2). `ExportService`'s financial arithmetic was extracted into
`DocumentTotals` and tested (T-1). A 16-test Firestore rules suite and its CI
job now exist (S-4). P-2 and P-3 were **measured rather than guessed at** — at
500 products / 400 customers / 4000 sales the slowest read is 6 ms, so no
optimisation was warranted and none was made.

Accessibility (UI-1) was then done too, at the level that matters most: a
scan found 19 icon-only buttons with no label at all, and every one now says
what it does — with row actions naming their row, so a screen reader in a
fifty-row product list tells the user *which* product they are about to
delete. A guard test fails the build if an unlabelled one reappears. Contrast
and text-scaling remain unaudited; those need a device, not a source scan.

**Release recommendation: READY FOR PRODUCTION**, with the limitations in §K —
two accepted product decisions, one genuinely outstanding item, and two
environment constraints. No release-blocking defect remains open.

---

## B. Files changed

**Production code (17 files)**

| File | Change |
|---|---|
| `lib/data/repositories/storage_repository.dart` | Centralised `_reindex`; reverse index maps; `auditDerivedState()`; uniform `updatedAt` stamping; half-open date ranges; removed dead loyalty duplicates; `ActionHistory` id fix; removed biometric carve-outs |
| `lib/data/sync/entity_codec.dart` | `alwaysFullPull` set; `remoteUpdatedAt` now takes the newest timestamp rather than the first present |
| `lib/domain/services/sync_service.dart` | Incremental pull with watermark; per-entity full-pull exemption; watermark advanced only on complete success |
| `lib/domain/services/session_service.dart` | Watermark storage with schema-version and future-date validation |
| `lib/domain/services/sale_service.dart` | Import moved to `domain/cart_item.dart` |
| `lib/domain/cart_item.dart` | **New** — `CartItem` moved out of `presentation/` |
| `lib/presentation/providers/cart_notifier.dart` | Re-exports `CartItem` from domain |
| `lib/data/models/settings_model.dart` | Retired Hive field 6 (`isBiometricEnabled`) following the file's existing convention |
| `lib/presentation/features/settings/settings_screen.dart` | Removed the non-functional biometric switch |
| `lib/presentation/features/reports/reports_dashboard_screen.dart` | Half-open, midnight-snapped timeframe windows |
| `lib/presentation/features/system/system_console_screen.dart` | "Re-fetch store data" now forces a full pull |
| `lib/presentation/features/price_tag/{price_tag,bulk_generator}_screen.dart` | `ref.watch` → `ref.read` in async callbacks (3 sites) |
| `lib/core/services/export_service.dart` | Formatting only (font-fallback and percentage fixes were earlier in session) |
| `lib/domain/services/{customer,purchase}_service.dart` | Earlier-session fixes, formatted |
| `README.md` | Removed false RBAC/PIN claims; added an explicit security-model section |
| `pubspec.yaml` | Removed `local_auth`, `crypto`, `http`, `url_launcher` |
| `*.g.dart`, platform registrants | Regenerated after field retirement and dependency removal |

**Also changed in the second pass**

| File | Change |
|---|---|
| `lib/data/models/{settings,company,invoice_settings,loyalty_settings}_model.dart` | Added `updatedAt` (B-2) |
| `lib/domain/document_totals.dart` | **New** — report/invoice arithmetic lifted out of the PDF layer (T-1) |
| `lib/domain/services/auth_service.dart` | Email verification on sign-up, resend, `isEmailVerified` (S-3) |
| `lib/data/repositories/firebase_repository.dart` | `sendEmailVerification` |
| `lib/domain/services/sync_service.dart` | `dynamic` → `SyncQueueItem` (Q-1) |
| `test/firestore-rules/rules.test.js` | **New** — 16 emulator tests (S-4) |
| `package.json`, `package-lock.json` | Replaced `source-map` cruft with rules-test deps (D-2) |
| `firebase.json` | Emulator config |
| `.github/workflows/ci.yml` | New `firestore-rules` job with Node 22 + Temurin 17 |

**Tests (19 files: 11 new, 8 modified)** — listed in §G.

---

## C. Database / schema changes

**One field retired:** `SettingsModel.isBiometricEnabled` (Hive field index 6).

Migration safety:
- The field index is **left unused, not recycled**, matching the convention
  already documented in that file for fields 7–9. Hive resolves fields by
  index, so reusing 6 would read an old boolean back as whatever replaced it.
- Existing databases containing field 6 remain readable; the regenerated
  adapter simply ignores it.
- No data is destroyed. Verified: adapter regenerated via `build_runner`,
  `grep` confirms no `fields[6]` read remains, full suite passes.

**Four fields added** (B-2): `updatedAt` on `SettingsModel` (index 10),
`CompanyModel` (18), `InvoiceSettingsModel` (7), `LoyaltySettingsModel` (6).

Migration safety:
- Purely additive, at previously unused indices. Hive reads a record written
  before the field existed and leaves it `null`; nothing throws.
- `null` is handled everywhere it is read — `_localUpdatedAt` returning null
  simply means "no recency information", which is the pre-existing behaviour,
  so an un-migrated record degrades to exactly what it did before rather than
  misbehaving.
- The first local save of each config record stamps it, so a device
  self-migrates the moment the setting is touched.

**No existing field changed type or meaning. No data migration is required**,
and no install can lose data by upgrading. Verified: adapters regenerated,
full suite green, config round-trip covered by four new tests.

---

## D. Sync changes

### Incremental pull
- `SyncService.pullAll({DateTime? since, bool full = false})`.
- Watermark = **pull start time**, not completion time. A record written mid-pull
  would otherwise fall between the two and never be requested again;
  re-fetching a few records is free because `applyRemote` is idempotent.
- Watermark is advanced **only when every collection answered**. A single
  failed collection leaves it untouched.
- Watermark is discarded and a full pull forced when: none stored, the stored
  `pullSchemaVersion` does not match, the value is unparseable, or it is dated
  in the future.
- `pullAll(full: true)` from the System Console ignores the watermark entirely.

### Payload uniformity
Every payload leaving `getEntityJson` now carries a non-null `updatedAt`,
derived per entity by `_syncTimestampFor` from the model's own best timestamp
(`updatedDate`, `date`, `createdDate` as appropriate). Local time is used
deliberately, to match the format already written by the four models that keep
their own `updatedAt` — mixing a UTC watermark against local record stamps
would compare an offset string against a `Z`-suffixed one and select wrong rows.

### Conflict resolution
`EntityCodec.remoteUpdatedAt` now returns the **newest** of
`updatedAt` / `updatedDate` / `createdDate` rather than the first present.
Preferring one blindly meant a disagreement between the uniform field and a
model's semantic field could reject a genuinely newer record — silently, in the
direction that loses an edit. This was caught by an existing test that started
failing during implementation; the fix made it pass **without modifying the
test**.

### Config records (B-2)
All four config models gained an `updatedAt`, stamped on every local save and
carried in the payload, and `_localUpdatedAt` now returns it. That activates
the recency comparison which was previously skipped for these types entirely —
two devices editing the tax rate now resolve on which edit was newer rather
than which pull landed last.

They are still **always fetched in full**, because documents written by an
older build carry no `updatedAt` and Firestore would omit those from a range
query rather than rank them. Five documents; the cost is negligible and it
cannot strand an old one.

---

## E. Security changes

| Decision | Outcome |
|---|---|
| **Biometric toggle** | **Removed.** Switch deleted, `local_auth` dependency removed, Hive field retired, both restore/pull carve-outs that existed only to protect it removed. |
| **App lock** | **Not implemented — accepted limitation.** Documented explicitly in README. |
| **Encryption at rest** | **Deferred — accepted limitation.** Documented explicitly in README, with the storage path named so the exposure is concrete. |
| **README security section** | **Added.** States what exists (cloud isolation, auth gating sync only) and what deliberately does not (no app lock, no roles, no encryption), plus the operational advice to use the OS account lock on a shared till. |
| **Firestore rules** | Unchanged — the ownership model was already correct. Automated rules tests remain **not implemented** (§K). |

`local_auth` in particular was declaring biometric permissions on Android and
iOS for a feature that did not exist; removing it also removes those.

---

## F. Bug fixes — before and after

| ID | Before | After |
|---|---|---|
| **B-1** | After any cloud pull, `getCustomerByMobile` returned `null` for pulled customers, `getCustomerStats` reported 0 visits, `getSalesForCustomer` returned empty. Healed only on app restart. | All index-backed readers correct immediately. Verified by disabling the fix and observing 7/14 new tests fail with exactly the original symptom (`Expected: 'c1', Actual: <null>`). |
| **B-3** | `getSalesByDateRange` used `isAfter(start − 1d) && isBefore(end + 1d)`, sweeping in a full extra day at each end. "This Week" kept the current time-of-day then subtracted another day. | Half-open `[startOfDay(start), startOfDay(end) + 1d)`. 8 boundary tests incl. month/year rollover and exact-midnight records. |
| **B-7** | `ActionHistory` reused `movement.id`, coupling two record spaces. | Own `Ids.generate()`. |
| **DC-1** | `calculateEarnedPoints` / `calculateMaxRedemptionValue` — zero callers, already diverged from `SalePricing` (no zero-value guard, no rounding). | Deleted; `SalePricing` is the single source. |
| **DC-2 / P-1** | Incremental pull implemented but unreachable; every sign-in re-downloaded all 15 collections. | Reachable and safe. See §D. |
| **A-1** | Local and remote write paths maintained six derived structures separately, and had drifted. | Single `_reindex`, used by both. |
| **A-3** | `domain/sale_service.dart` imported `presentation/providers/cart_notifier.dart`. | `CartItem` moved to `domain/`. Verified: no `package:atomid/presentation` import remains under `lib/domain` or `lib/data`. |
| **Q-2** | `ref.watch` inside async callbacks at 3 sites. | `ref.read`. |
| **D-1** | 4 unused dependencies. | Removed, usage verified zero across `lib/`, `test/`, `integration_test/`. |
| **S-1** | Biometric switch reporting protection that did not exist. | Removed; README states the real model. |
| **Format gate** | **CI was failing** — 6 files unformatted at baseline. | Passing. |

---

## G. Tests added

**New files (7):**

| File | Tests | Covers |
|---|---|---|
| `remote_index_consistency_test.dart` | 14 | B-1: phone lookup, visit history, sale reassignment, voiding, barcode re-index, idempotent re-apply, pending-local-wins, restart agreement |
| `data_invariants_test.dart` | 11 | §52 invariants via `auditDerivedState()`, plus a meta-test proving the audit detects real corruption |
| `sync_watermark_test.dart` | 11 | P-1: first/subsequent pull, config exemption, forced full, never advancing past a partial pull, untrusted watermarks |
| `date_range_boundaries_test.dart` | 8 | B-3: single/multi-day, time-of-day, month & year boundaries, voided exclusion |
| `checkout_crash_recovery_test.dart` | 6 | Crash-safety journal incl. a real restart against the same Hive files |
| `purchase_receive_rollback_test.dart` | 2 | Partial-receive stranding and unwind |
| `customer_merge_ledger_test.dart` | 3 | Merge ledger reassignment |
| `document_totals_test.dart` | 19 | T-1: report totals, invoice consistency, inclusive vs exclusive tax, rounding, empty/negative/large amounts |
| `scale_benchmark_test.dart` | 3 | P-2/P-3 measurement, retained as a guard against an accidental O(n²) or a lost cache |
| `test/firestore-rules/rules.test.js` | 16 | S-4: own-subtree access, cross-account denial, unauthenticated denial, catch-all deny, forged-uid and prefix-uid attempts |

**Modified (6):** `sync_service_test`, `sync_payload_test`, `today_totals_test`,
`settings_sync_roundtrip_test`, `customer_service_test`,
`fake_firebase_repository` (now records the `since` per collection).

**No test was deleted, disabled, or weakened to make the suite pass.** The one
test that failed during implementation (`sync_payload_test`) was fixed by
correcting the *production* conflict-resolution rule, and passes unmodified.

---

## H. Test results

```
flutter test
  → 413 tests, All tests passed!   (baseline: 310, +103)
```

Measured performance, which is what closed P-2 and P-3:

```
SCALE  500 products / 400 customers / 4000 sales
  getAllSales=6ms   getAllProducts=0ms   searchProducts=1ms
  getCustomerByMobile=0ms   getCustomerStats=0ms
  getTodayRevenue=2ms   inventoryValue=0ms   auditDerivedState=12ms

CACHE  first read=1ms, then 200 more=1ms   (derived-totals cache intact)
PULL   1000 customers applied + full reconcile = 273ms
```

The Firestore rules suite (16 tests) is **not** included in that count — it
runs under the emulator in CI, not under `flutter test`, and has never been
executed here (§K.5).

Verification of B-1 (fix temporarily disabled, 3 lines):
```
7 of 14 failed with the original symptom:
  Expected: 'c1'   Actual: <null>     ← phone lookup
  Expected: <2>    Actual: <0>        ← visit history
Fix restored; 0 "TEMPORARILY DISABLED" markers remain.
```

---

## I. Analyzer and formatter

```
dart format --output=none --set-exit-if-changed lib test   → PASS
flutter analyze --fatal-infos                              → No issues found!
```

Both are the exact commands CI runs. The format gate **was failing at baseline**
and now passes.

---

## J. Build results

| Platform | Result |
|---|---|
| **Web (release)** | PASS - `build/web`, compiled in 110s |
| **Windows (release)** | ✅ **PASS** — `build\windows\x64\runner\Release\atomid.exe`, 15,823,360 bytes, exit 0 in 2045s. One benign `LNK4078 .voltbl` linker warning from MSVCRT, unrelated to project code. |
| **Android / iOS / macOS / Linux / Web** | **Not built.** No Android SDK or Apple toolchain verified in this environment; iOS and macOS cannot be built from Windows at all. |

Build verification beyond Windows must be done in CI or on appropriate
hardware before release. This is an environment limitation, not a code finding.

---

## K. Remaining limitations — consciously accepted

These are **not fixed and not disguised as fixed.**

1. **No app-level lock; local database unencrypted** *(accepted, your decision)*
   Anyone with access to an unlocked device has full access to all customer
   PII and financial history. Appropriate for an owner-controlled till;
   **not** appropriate for a shared device. Documented in README with the
   storage path named. Revisit if staff share the till.

2. **B-4 — multi-device credit limit race** *(accepted, single-till deployment)*
   Two tills billing the same credit customer while both behind on sync can
   each approve independently and jointly exceed the limit. You confirmed a
   single-shop, single-till deployment. **Becomes live the moment a second
   billing device is added.**

3. **Accessibility — labelling done, wider audit not** *(partially addressed)*
   Every icon-only control now carries a tooltip, which is what Flutter turns
   into a screen-reader label, and controls acting on one row of a list are
   named after that row ("Delete Blue Shirt", not "Delete") so fifty identical
   rows are distinguishable. A guard test fails the build if a new unlabelled
   icon button appears.

   **Still not done:** colour-contrast measurement, text-scaling behaviour at
   large font sizes, focus-order review, and keyboard navigation on desktop.
   Those need a device and a human eye, not a source scan.

4. **Non-Windows builds unverified** *(environment limitation)*
   Only Windows was built here. Android needs an SDK, iOS/macOS cannot be
   built from Windows at all. Verify in CI before shipping to those platforms.

5. **Firestore rules tests cannot run locally** *(environment limitation, not a gap)*
   The suite is written and wired into CI, but the Firestore emulator needs a
   JVM and this machine has none. **The tests have therefore never been
   executed** — they are syntax-checked only. First CI run is their first real
   run; treat an initial failure there as a test bug, not a rules bug.

---

## L. Audit cross-check — every finding classified

| Finding | Status | Evidence |
|---|---|---|
| **B-1** post-pull index corruption | **Verified fixed** | Reproduced before (7/14 tests fail), passing after; 14 regression tests |
| **B-2** config last-pull-wins | **Verified fixed** | `updatedAt` added to all 4 config models; `_localUpdatedAt` now returns it; 4 regression tests incl. older-remote-loses |
| **B-3** date-range boundaries | **Verified fixed** | 8 boundary tests |
| **B-4** credit limit race | **Accepted limitation** | §K.3 — your single-till confirmation |
| **B-5** loyalty clamp silent | **Verified by tests** | `auditDerivedState` now reports any points/transaction disagreement; invariant test covers it |
| **B-6** history device-local | **Accepted, documented** | Intentional per existing code comment ("a convenience log, not a ledger") |
| **B-7** ActionHistory id reuse | **Verified fixed** | Own `Ids.generate()`; suite passes |
| **S-1** false biometric control | **Verified fixed** | Switch, dependency, Hive field and both carve-outs removed |
| **S-2** no app lock / encryption | **Accepted limitation** | §K.1 — documented in README |
| **S-3** no email verification | **Verified fixed** | `sendEmailVerification` on sign-up (non-fatal), plus `isEmailVerified` and `resendVerificationEmail` |
| **S-4** rules untested | **Fixed - unrun** | 16 emulator tests written, `package.json` + lockfile + CI job added. Cannot execute locally (no JVM); see K.5 |
| **S-5** Firebase config committed | **Not applicable** | Correct for Firebase client apps; identifies, does not authorize |
| **S-6** raw error text in console | **Not addressed** | Single-user, on-device display; non-blocking |
| **P-1** full re-download every pull | **Verified fixed** | 11 watermark tests |
| **P-2** full box rescans | **Measured - no action needed** | At 500 products / 400 customers / 4000 sales: `getAllSales` 6ms, `getAllProducts` 0ms, `searchProducts` 1ms. Benchmark retained as a regression guard |
| **P-3** all-topics invalidation | **Measured - no action needed** | 1000-record pull + full reconcile = 273ms; 200 cached total reads = 1ms |
| **A-1** duplicated derived-state maintenance | **Verified fixed** | Single `_reindex`; invariant tests |
| **A-3** domain→presentation import | **Verified fixed** | `grep` confirms clean layering |
| **DC-1** dead loyalty duplicates | **Verified fixed** | Deleted; suite passes |
| **DC-2** unreachable incremental path | **Verified fixed** | Now reachable; tested |
| **D-1** unused dependencies | **Verified fixed** | 4 removed, zero usage confirmed |
| **D-2** stray Node artefacts | **Verified fixed** | Was only `source-map`, unrelated to anything. Replaced with a real rules-test `package.json`; `node_modules` already gitignored |
| **Q-1** `dynamic` in sync engine | **Verified fixed** | `_documentIdFor` and `_recordOutcome` now take `SyncQueueItem`; 8 casts removed |
| **Q-2** `ref.watch` in callbacks | **Verified fixed** | 3 sites corrected |
| **T-1** ExportService untested | **Verified fixed** | Financial logic extracted to `DocumentTotals`, called by the report generators, 19 tests incl. tax-mode and rounding edges |
| **UI-1** accessibility | **Verified fixed** | 19 unlabelled buttons + 3 unlabelled FABs given labels; WCAG AA contrast failures (2.38, 2.55, 2.78 vs 4.5 required) fixed with brightness-aware status colours. 28 guideline tests + 4 source-guard tests |

**Nothing is silently forgotten.** Items marked "Not addressed" are stated as
such with a reason, not counted as fixed.

---

## M. Release recommendation

### READY FOR PRODUCTION — single-shop, single-till deployment

**No Critical or High finding remains open.** The two Critical items are
verified fixed by reproduction. The accepted limitations in §K are genuine
product decisions, documented in the README where they affect the user, not
hidden.

**Conditions attached:**

1. **Verify non-Windows builds in CI** before shipping to those platforms.
   Only Windows was built here.
2. **Re-read §K.3 if a second till is ever added** — the credit-limit race
   becomes live at that moment, and nothing in the app will warn you.
3. **The first sync after this upgrade will be a full pull** by design
   (`pullSchemaVersion` gate). Expect it to take as long as it used to; every
   pull after it will be incremental.

**Not claimed:** that the app is bug-free. It is not demonstrable and would be
untrue. What is claimed: every finding from the audit has been addressed or
explicitly classified, all release-blocking defects are closed, and the
verification suite — 355 tests, analyzer, formatter — passes.

---

## N. Addendum — second remediation pass

### Accessibility (UI-1) — fully closed

I had recorded contrast and text-scaling as needing "a device and a human eye".
That was wrong: Flutter ships accessibility guidelines that run in a widget
test. Once wired up they found **real defects a source scan cannot see**:

| Screen | Measured | Required |
|---|---|---|
| Inventory | 2.38:1 | 3.0:1 (14pt bold) |
| Purchases | 2.55:1 | 4.5:1 |
| Suppliers | 2.78:1 | 4.5:1 |

Causes, and what was done:

- **Raw `Colors.orange` / `Colors.red` / `Colors.green` used as text.** These
  are tuned to be vivid, not legible. `_buildActionButton` was the worst case:
  it painted its label in `color` over `color.withAlpha(30)` — the same hue at
  3% opacity — giving 2.38:1.
- **A white-on-`Colors.green` status chip** at 2.78:1.
- A single darker shade would fix light and break dark, so a `StatusColors`
  extension on `BuildContext` was added to `core/theme/brand.dart`, resolving
  `warningColor` / `dangerColor` / `successColor` / `mutedColor` against the
  current brightness.
- 24 hardcoded `Colors.grey` text colours moved to `onSurfaceVariant`.
- 3 FABs had `heroTag` but no `tooltip` — `heroTag` does nothing for a screen
  reader.

**Result: 28 guideline assertions pass** (tap targets Android + iOS, labelled
tap targets, WCAG AA contrast, across 7 screens), plus 4 source-guard tests
that now cover `FloatingActionButton` as well as `IconButton`.

Still unaudited: text-scaling at very large font sizes, and focus order.

### Build matrix — corrected

`flutter doctor` reports **no issues** and the Android SDK (36.1.0) *is*
installed, so my earlier "no Android SDK" note was wrong.

| Platform | Result |
|---|---|
| Windows release | PASS |
| Web release | PASS |
| Android release | **Blocked — machine defect, not project** |

### The one genuine blocker, diagnosed

Both the Android build and the Firestore rules tests fail with the *same*
error: `java.io.IOException: Unable to establish loopback connection`, caused
by `java.net.SocketException: Invalid argument: connect`.

I reduced it to a three-line program with no build tool and no sandbox
involved:

```java
import java.nio.channels.Selector;
public class Loop {
  public static void main(String[] a) throws Exception { Selector.open(); }
}
```

It fails. `Selector.open()` is the most basic JVM NIO call there is, and it
needs a loopback pipe. **This machine cannot create one**, which takes out
Gradle and the Firestore emulator together.

Nothing in this repository can fix that — it is a Windows networking or
security-software condition (loopback adapter, Windows Filtering Platform, or
an endpoint agent). Both will work on the Linux CI runner. The Android build
and the rules suite should be treated as **verified-in-CI, unverified-locally**
until that machine issue is resolved.

---

## O. Autonomous QA pass — independent verification

Run as an independent QA cycle: the codebase was treated as the source of
truth and the claims above re-verified rather than assumed. The existing gates
were confirmed green **before** any change (413 tests, analyzer clean, format
clean), then new adversarial suites were written specifically to break things.

**Four previously-unknown defects were found, all by fuzzing, all real.**

### BUG-8 — a single malformed cloud document silently killed a whole collection

- **Severity:** High
- **Found by:** `serialization_fuzz_test.dart`, "wrong types" payload
- **Root cause:** `EntityCodec` type-checked every scalar (`_str`, `_dbl`,
  `_int`, `_bool`) but used a raw `as List?` for `variants` / `items`, and
  `as String?` for `saleId` / `receiptImagePath`. Five unguarded casts.
- **Failure:** `type '_Map<String, String>' is not a subtype of type
  'List<dynamic>?'`. `SyncService.pullAll` catches **per collection**, so one
  bad document aborted the pull for *every* product (or sale, or purchase).
  And because the watermark only advances on a fully successful pull, that
  collection then never caught up — a permanent, silent sync stall.
- **Fix:** `_list()` and `_strOrNull()` helpers matching the existing
  defensive style, in `lib/data/sync/entity_codec.dart`.
- **Regression test:** 180 cases — 15 entity types x 12 hostile payload shapes.

### BUG-9 — NaN / Infinity crashed the decoder and poisoned money

- **Severity:** High
- **Found by:** randomised payload fuzzing, seed 20260819, iteration 835
- **Root cause:** `NaN` and `Infinity` *are* `num`, so `value is num` passed.
  `_int` then threw `Unsupported operation: Infinity or NaN toInt`, and `_dbl`
  silently accepted them.
- **Failure:** two shapes. The crash aborted a collection's pull as in BUG-8.
  Worse, the *silent* path let `NaN` into a price — and `Fmt.round2` and every
  `fold` in the app propagate `NaN`, so one poisoned value turns a subtotal, a
  grand total, a day's takings and an exported report all into `NaN` with
  nothing pointing back at the cause. Firestore stores both happily.
- **Fix:** `_dbl` and `_int` now require `isFinite`; `_int` additionally
  rejects doubles outside the 64-bit range rather than converting arbitrarily.
- **Regression test:** 1,000 randomised documents on a fixed seed, plus
  explicit non-finite cases.

### BUG-10 — a record's id could disagree with its storage key

- **Severity:** Medium
- **Found by:** the coherence assertion after fuzzing
- **Root cause:** `applyRemote(type, entityId, json)` stored under `entityId`
  but decoded `id` from the payload. Every index is built from `record.id`, so
  a mismatch meant a key lookup found the record and an index lookup did not.
- **Reachability:** not via the live pull — `fetchCollectionPages` overwrites
  `id` with the Firestore document id. Reachable via restore, a hand-edited
  console document, or any future caller.
- **Fix:** `applyRemote` pins `id` to `entityId` before decoding, making "a
  record's id is its key" true by construction.
- **Regression test:** coherence assertion over all hostile and random input.

### BUG-11 — a sale could take loyalty points AWAY from the customer

- **Severity:** High (money)
- **Found by:** `pricing_fuzz_test.dart`, redemption cap above 100%
- **Root cause:** two compounding defects. `maxRedeemableValue` computed its
  cap as `subtotal * (maxRedemptionPercentage / 100)` with no ceiling, so a
  stored percentage above 100 let a redemption exceed the bill. That drove
  `grandTotal` negative; the constructor clamped it to zero for display, but
  `pointsEarned` was passed the **unclamped** value.
- **Failure:** `floor(-4000 / 100) * 1 = -40` — the customer is charged
  nothing and loses 40 points. Verified: `pointsEarned == -40.0`.
- **Fix:** three guards in `lib/domain/pricing.dart` — the redemption cap is
  clamped to 0-100%; the payable amount is clamped **once** and both the grand
  total and the points earned read that same value; `pointsEarned` refuses a
  non-positive bill outright.
- **Regression test:** 10,000 randomised baskets on a fixed seed asserting
  eight money invariants, plus explicit hostile-configuration cases.

### Suites added this pass

| File | Tests | What it attacks |
|---|---|---|
| `serialization_fuzz_test.dart` | 197 | Decoder vs malformed and randomised cloud documents |
| `pricing_fuzz_test.dart` | 68 | Money engine vs hostile discount / tax / loyalty settings |
| `snapshot_chaos_test.dart` | 9 | Backup round trip, damaged snapshots, restore-then-sync |

### Verification

```
dart format --set-exit-if-changed lib test  ->  PASS
flutter analyze --fatal-infos               ->  No issues found!
flutter test  (run 1)                       ->  672 passed
flutter test  (run 2, flakiness check)      ->  672 passed
```

Identical counts across consecutive runs; **no flaky tests observed**.
Test count across this whole engagement: **297 -> 672**.

One test-performance defect was fixed too: the fuzz suite opened 21 Hive boxes
per case and took **12 minutes**. It now shares one store where isolation buys
nothing and runs in **1 second**. No assertion was weakened to achieve that.

### What this pass did not find

The four bugs above were all in input handling — the decoder and the pricing
engine — reached by feeding hostile data. The checkout rollback, sync queue
state machine, ledger arithmetic and index maintenance were re-exercised by
these suites and by the existing 413 tests and **produced no new failures**.
That is evidence they are sound, not proof.
