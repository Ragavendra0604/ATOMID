# Atomid — Manual Test Guide

Written for testing **what actually changed**. Everything here is a real
defect that existed in this codebase and is now fixed — so if any of these
steps behaves as described in "the old broken behaviour", something regressed.

---

## 0. Get a current build

The release `.exe` on disk predates the latest fixes. Rebuild before testing:

```bash
flutter run -d windows
```

That gives you hot reload and a console showing errors — better for testing
than a release build. Use `flutter build windows --release` only when you want
to test the shipping artifact.

Other targets:

```bash
flutter run -d chrome
```

```bash
flutter run -d edge
```

**Where your data lives** (you'll need this for the sync test):
`%APPDATA%\com.example\atomid\db` — or `%LOCALAPPDATA%\atomid\db` if your
profile is on OneDrive. Renaming that folder makes the app start as a brand
new device.

---

## 1. HIGHEST PRIORITY — the cloud sync bug (B-1)

This was the worst defect found. It only shows on a **second device**, which
is exactly why it survived so long.

### Setup — "Device A"
1. Launch the app, sign in.
2. Create a customer with a real phone number, e.g. **Asha / 9876543210**.
3. Create a product with a barcode.
4. Ring up **2–3 sales** for Asha through the POS.
5. Open **Settings → System Console** and confirm the sync log shows SUCCESS.
   Wait until the cloud indicator is idle.

### Now simulate "Device B"
6. **Close the app completely.**
7. Rename the data folder above (e.g. `db` → `db_backup`). Don't delete it —
   renaming lets you get your data back.
8. Launch the app again. It should start empty.
9. Sign in with the same account. Wait for the pull to finish.

### The actual test — do this WITHOUT restarting
10. Go to **POS**. In the customer lookup, type **9876543210**.

| | |
|---|---|
| ✅ **Correct** | Asha is found instantly |
| ❌ **The bug** | "no customer found" — and you'd create a duplicate |

11. Open Asha's customer detail screen.

| | |
|---|---|
| ✅ **Correct** | Shows 2–3 visits, her spend, her ledger |
| ❌ **The bug** | "First visit", empty history |

12. Scan or type the product's barcode in POS.

| | |
|---|---|
| ✅ **Correct** | Product found |
| ❌ **The bug** | Not found |

> **The critical detail:** the old bug *healed itself on restart*. So step 10
> must be done **before** you close the app. If you restart first, you'll see
> correct behaviour either way and the test proves nothing.

13. When done, delete the new `db` folder and rename `db_backup` back.

---

## 2. Money — the loyalty points bug (BUG-11)

A misconfigured loyalty setting could make a sale **take points away** from a
customer.

1. **Settings → Loyalty settings.** Set:
   - Points per spend: something normal (1 point per ₹100)
   - **Max redemption percentage: try 150** (or the highest it lets you enter)
   - Point redemption value: 10
2. Give a customer a healthy points balance (ring up several sales first).
3. Ring up a **small** sale — say ₹200 — for that customer, and tick
   **redeem points**.

| | |
|---|---|
| ✅ **Correct** | Discount never exceeds the bill. Total is ₹0 at worst. Points earned is **0 or positive** |
| ❌ **The bug** | Total goes negative, and the customer's points balance **drops** after the sale |

4. Check the customer's loyalty history — no negative "earn" entry.

### Also worth trying
- 100% discount → total exactly ₹0, never negative
- Discount typed as `999` → clamped, not applied literally
- A 0.01 item with 33.33% discount → no rounding weirdness on the invoice
- Switch tax between **inclusive** and **exclusive** and confirm:
  - inclusive: shelf price is what the customer pays
  - exclusive: tax is added on top

---

## 3. Purchase receiving (B-2 from the original audit)

1. Create a purchase order with **2–3 different products**. Issue it.
2. Now **delete one of those products** from the catalogue.
3. Go back to the PO and press **Receive**.

| | |
|---|---|
| ✅ **Correct** | Clear error naming the missing product. Order stays **Issued** and editable. **No** stock moved, supplier **not** credited |
| ❌ **The bug** | Order flips to "Received", some stock moved, supplier never credited — and you can't cancel or retry it |

4. Re-add the product (or remove the line), press Receive again — it should now
   succeed and credit the supplier.

---

## 4. Customer merge (ledger integrity)

1. Create two customers, both with some sales/ledger activity.
2. Merge one into the other.

| | |
|---|---|
| ✅ **Correct** | Combined balance is right **and** the ledger shows every transaction explaining it |
| ❌ **The bug** | Balance looks right but the ledger rows are missing — a number with nothing behind it |

---

## 5. Report date boundaries (B-3)

1. Ring up a sale, then check **Reports → Today**.
2. Compare "Today" against the actual sales list.

| | |
|---|---|
| ✅ **Correct** | Only today's sales counted |
| ❌ **The bug** | Yesterday's takings bleeding into today's figure |

Worth checking around midnight, and on the 1st of a month, since those are
where the old off-by-a-day showed up.

---

## 6. Crash recovery — the impressive one

1. Start a checkout with **several items** for a customer.
2. **Kill the app mid-checkout** — Task Manager → End Task, right as you
   confirm. (Or pull the power if you're feeling committed.)
3. Relaunch.

| | |
|---|---|
| ✅ **Correct** | The half-finished sale is gone. Stock is back where it was. Customer's balance and points unchanged. **History → an entry saying the interrupted sale was reversed** |
| ❌ **Broken** | A sale exists with stock deducted but no ledger entry, or vice versa |

4. Cross-check: **Settings → System Console** and the stock figures.

---

## 7. Offline behaviour

1. Turn off Wi-Fi / unplug the network.
2. Do a full day's work: sell, add a customer, stock in, record an expense.
   Everything must work normally.
3. Reconnect.
4. **System Console** → watch the queue drain to zero.

| | |
|---|---|
| ✅ **Correct** | Everything works offline; queue drains on reconnect |
| ❌ **Broken** | Any screen blocks or errors while offline |

---

## 8. Accessibility (quick check)

Hover over any icon-only button — the edit/delete icons in the product list,
the FABs, the scanner controls.

| | |
|---|---|
| ✅ **Correct** | Every one shows a tooltip. List actions name their row: "Delete Blue Shirt", not just "Delete" |
| ❌ **Broken** | A button with no tooltip |

Also glance at the **Inventory** dashboard — the "Low Stock" / "Out of Stock"
text and the Stock In/Out buttons should be clearly readable, not washed-out
pale orange/green on a pale tint.

---

## 9. Where to look when something seems wrong

**Settings → System Console** is your diagnostic screen:
- Sync log with SUCCESS/FAILED per record
- Failed items only
- "Retry failed"
- **"Re-fetch store data"** — forces a full pull, ignoring the incremental
  watermark. This is the button to press if you suspect sync missed something.

**History screen** shows the audit trail, including automatic reversals of
interrupted sales.

If you hit something odd, the most useful thing you can send me is: what you
did, what you expected, what happened, plus a screenshot of the System Console.

---

## What I could NOT test for you here

- **Android build** — this machine's JVM can't open a loopback socket, so
  Gradle won't run. Needs fixing on the machine, or build in CI.
- **Real two-device sync** — I only have one machine; the folder-rename trick
  above is the closest single-machine equivalent.
- **Actual printing** — PDF generation is tested, physical printers are not.
- **Camera barcode scanning / OCR** — needs a real device with a camera.
