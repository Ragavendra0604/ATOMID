<p align="center">
  <img src="assets/images/logo.png" alt="Atomid Logo" width="120" style="border-radius: 20px;" />
</p>

<h1 align="center">Atomid</h1>

<p align="center">
  <strong>⚡ Offline-first retail & POS platform — built with Flutter</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.47.1-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Firebase-Auth%20%7C%20Firestore-FFCA28?logo=firebase&logoColor=black" alt="Firebase" />
  <img src="https://img.shields.io/badge/Hive%20CE-Local%20DB-FF6F00" alt="Hive CE" />
  <img src="https://img.shields.io/badge/State-Riverpod-1E88E5" alt="Riverpod" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-8BC34A" alt="Platforms" />
  <img src="https://img.shields.io/badge/version-1.0.0-blueviolet" alt="Version" />
</p>

---

## ✨ Overview

**Atomid** is a cross-platform retail management and point-of-sale application designed for businesses that need **rock-solid offline reliability** with seamless cloud synchronization. Every transaction, inventory change, and customer interaction works without internet — then automatically syncs when connectivity is restored.

---

## 🎯 Key Features

| Feature | Description |
| :--- | :--- |
| 🛒 **POS & Billing** | Fast barcode scanning checkout with cart management, discounts, and receipt printing |
| 📦 **Inventory Management** | Stock-in / stock-out tracking with immutable audit logs |
| 👥 **Customer CRM** | Customer profiles, ledger history, and loyalty points |
| 🔄 **Two-Way Sync** | Hive local storage ⇄ Firestore, account-scoped, with backoff, dead-letter and conflict resolution |
| 📊 **Dashboard & Reports** | Revenue analytics, low-stock alerts, and transaction history |
| 🧾 **PDF Export** | Generate and print invoices, reports, and barcode sheets |
| 🧾 **Tax & Loyalty** | Inclusive or exclusive tax, configurable reward points |
| 📱 **Platforms** | Android · Web · Windows (cloud sync) · iOS/macOS/Linux (device-only until configured) |

---

## 🔐 Security model — what this app does and does not do

Stated plainly, because a POS holds customer records and financial history and
it should be obvious what is protecting them.

**What exists**

- **Cloud isolation.** Everything a device syncs lives under `/users/{uid}/…`
  in Firestore. The security rule is a single ownership condition, so an
  account can reach its own data and nothing else. Verified by an automated
  rules test suite.
- **Email/password authentication** via Firebase, which gates *cloud sync only*.

**What deliberately does not exist**

- **No app lock.** There is no PIN, password or biometric prompt on launch.
  Anyone with access to an unlocked device has full access to the app.
- **No roles or permissions.** This is a single-account product. There is no
  staff login, no PIN shift sign-in and no per-role permission model. An
  earlier version had these; they were removed, and the code no longer
  contains them.
- **No encryption at rest.** The local Hive database is unencrypted. On
  Windows it lives under `%USERPROFILE%\AppData\Local\atomid\db`.

These are appropriate for a till that one owner-operator controls physically.
**If the device is shared with staff, or left unattended in a public part of
the shop, treat the data on it as readable.** Use the operating system's own
account lock in that case.

Signing out affects cloud sync only — every screen keeps working offline, by
design.

---

## 🏗️ Tech Stack

```
Flutter / Dart          → Cross-platform UI framework
Hive CE                 → Lightning-fast local key-value database
Firebase Auth           → Email/password authentication
Cloud Firestore         → Real-time cloud synchronization
Riverpod                → Reactive state management
mobile_scanner          → Barcode / QR code scanning
connectivity_plus       → Network state monitoring
printing                → Receipt & document printing
```

---

## 📂 Project Structure

```
lib/
├── core/
│   ├── services/            # PDF export (invoices, receipts, reports, tags)
│   ├── theme/               # Light / dark themes
│   └── utils/               # Formatters, ids, errors, responsive helpers
├── data/
│   ├── models/              # Hive entities (Product, Sale, Customer …)
│   ├── repositories/        # StorageRepository, FirebaseRepository
│   └── sync/                # EntityCodec — Firestore encode/decode
├── domain/
│   ├── pricing.dart         # Pure sale arithmetic (tax, discounts, points)
│   └── services/            # Sale, Purchase, Customer, Sync, Session, Auth
├── presentation/
│   ├── features/            # Feature modules (billing, products, inventory …)
│   ├── providers/           # Riverpod providers (topic-driven refresh)
│   └── widgets/             # AppShell, guards, pickers, empty states
├── bootstrap.dart           # Composition root — builds every service once
├── main.dart                # App entry point
└── firebase_options.dart    # Per-platform Firebase config
```

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) **3.47.1**
  — the exact version CI pins. The formatter's output changes between Flutter
  releases, so a different local SDK will reformat files and fail CI's
  `--set-exit-if-changed` check even though nothing is wrong with the code.
- Android SDK (for Android builds)
- Xcode (for iOS/macOS builds)
- Firebase CLI *(optional — for advanced configuration)*

### Installation

```bash
# Clone the repository
git clone https://github.com/Ragavendra0604/ATOMID.git
cd atomid

# Install dependencies
flutter pub get

# Generate Hive adapters & code
flutter pub run build_runner build --delete-conflicting-outputs
```

### Firebase Setup

| Platform | Action |
| :--- | :--- |
| **All** | `flutterfire configure` regenerates `firebase_options.dart` and the native config files |
| **Android** | `google-services.json` in `android/app/` must list the current `applicationId` |
| **iOS / macOS** | `GoogleService-Info.plist` added to the Xcode target |

> The app id is **`com.atomid.store`**. Firebase keys its Android config on
> that exact string — if `google-services.json` was generated for a different
> one, the build fails with *No matching client found for package name*. Rerun
> `flutterfire configure` after any change to it.

### Run

```bash
flutter run
```

### Release signing (Android)

The repo ships **without** a keystore, so release builds fall back to the debug
key and Gradle prints a warning. That is fine for testing and rejected by Play.

Generate one before your first release:

```bash
keytool -genkey -v -keystore ~/atomid-upload.jks   -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties` (git-ignored):

```properties
storePassword=<the password you chose>
keyPassword=<the password you chose>
keyAlias=upload
storeFile=C:/Users/you/atomid-upload.jks
```

> **Back the `.jks` file up somewhere you will still have in five years.** It is
> the only thing that proves an update comes from you. Play refuses an upload
> signed with a different key, and there is no recovery — a lost keystore means
> the app can never be updated again.

### Build for Production

```bash
flutter build appbundle --release     # Android — what Play wants
flutter build apk --release           # Android APK (all ABIs, large)
flutter build appbundle --release     # Android App Bundle
flutter build ipa --release           # iOS (macOS host required)
flutter build web --release           # Web
flutter build windows --release       # Windows
flutter build macos --release         # macOS
flutter build linux --release         # Linux
```

---

## 🔄 Offline Sync Architecture

Atomid runs fully without internet. Writes are queued locally and uploaded when
connectivity returns; signing in pulls the store's history down so a second
device or a reinstall starts populated.

Every cloud document lives under `/stores/{storeId}/…`, so one business's data is
never reachable from another account.

```
┌──────────────┐       ┌────────────────┐     ┌─────────────────┐
│  User Action │────▶ │  Hive (Local)  │────▶│  Sync Queue     │
└──────────────┘       └────────────────┘     └────────┬────────┘
                                                       │
                                           ┌───────────▼───────────┐
                                           │   Network Detected?   │
                                           └───────────┬───────────┘
                                                   Yes ▼
                                           ┌───────────────────────┐
                                           │  Firestore Batch Sync │
                                           │  (20 items / batch)   │
                                           └───────────┬───────────┘
                                                       │
                                             ┌─────────┴─────────┐
                                             │                   │
                                       ✅ Success           ❌ Failure
                                       (Remove from         (Exponential backoff,
                                          queue)             5 tries, then parked
                                                             as DEAD for review)
```

---

## 🔐 Account & Sync

Atomid is a **single-user** app. Signing in is not a door into it — every
screen works signed out, on-device, offline. The account is the key to one
cloud copy and nothing else.

| | |
| :--- | :--- |
| **Signed out** | Everything works. Changes queue locally and wait. |
| **Signed in** | The queue drains to `/users/{uid}/…` whenever there is a connection. |

Security rules are one condition — an account owns its own subtree or it is
refused:

```
match /users/{userId}/{document=**} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

Deploy them before first use, or every sync is rejected:

```bash
firebase deploy --only firestore:rules
```

---

## 💾 Backup

Cloud sync is a **mirror**, not a backup: it replicates a deletion just as
faithfully as a sale. Backups are separate, under *Settings → Backup and
restore*.

- A full JSON snapshot, built from the same serialiser sync uses, so the two
  cannot drift apart.
- Written to a `.part` file and renamed into place — a crash mid-write leaves
  the previous backup intact rather than a truncated file that looks like one.
- **Restore is additive**: records with the same id are overwritten, missing
  ones are created, nothing is deleted. Restoring an old backup cannot destroy
  newer work.
- Ten most recent kept. Android writes to external storage so the file
  survives an uninstall; use **Send a copy** to get it off the device.

---

## 🧪 Testing

```bash
# Run all unit & widget tests
flutter test

# Static analysis
flutter analyze

# Code formatting
dart format .
```

Tests are located in:
- `test/unit/` — pricing, sale and purchase services, repository behaviour,
  index consistency after a cloud pull, crash recovery, sync payload
  round-trips, backup snapshots, formatters
- `test/widget/` — UI component and responsive-layout tests
- `test/support/` — `TestStore`, a real repository on a temporary Hive
  directory, and `FakeFirebaseRepository`, which subclasses the real cloud
  repository so a Firestore type leaking into the sync engine breaks the build
- `integration_test/` — boots the shipped `main()` against real Hive

CI runs `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos` and
`flutter test` on every push, then builds a release APK, an App Bundle and a
Windows binary as downloadable artifacts. A commit that cannot be packaged
fails there rather than on release day. The web deploy only runs after CI
passes.

The Firestore rules are tested in a separate job against the emulator, which
needs Node and a JVM rather than the Flutter toolchain:

```bash
npm ci
npm run test:rules
```

On a machine with neither, the same suite runs in a container — same Node 22
and Temurin 21 pairing CI uses, with the emulator jar baked into the image so
a rules edit re-runs in seconds:

```bash
docker compose -f docker/rules-tests.compose.yml run --rm --build rules-tests
```

`firestore.rules` and the test directory are bind-mounted, so editing either
and re-running does not rebuild the image.

### When something goes wrong on a till

**Settings → System → Diagnostics** lists local failures in the paths that
touch money or stock — a checkout that had to be reversed, a goods-in that
could not complete, an interrupted sale recovered at startup. Each entry names
the invoice or purchase order so a count can be checked by hand, and expands to
the underlying error for whoever is called out.

Entries marked as errors mean data may actually be inconsistent; those also
raise a banner on the Health tab so nobody has to go looking. Warnings are
failures the app fully undid on its own and are there for context only.

---

## 🤝 Contributing

1. **Open an issue** describing the change
2. **Fork & branch** — `git checkout -b feat/short-description`
3. **Run codegen** — `flutter pub run build_runner build --delete-conflicting-outputs`
4. **Add tests** for new behavior
5. **Ensure analysis passes** — `flutter analyze`
6. **Open a PR** with a clear description (include screenshots for UI changes)

---

## 📋 Development Conventions

- Always run `build_runner` after modifying annotated Hive models
- A field added to a model must also be added to `StorageRepository.getEntityJson`
  **and** `EntityCodec`, or it is silently dropped on sync — `sync_payload_test`
  guards this
- Money is formatted through `Fmt`, never interpolated raw
- Ids come from `Ids.generate()`, never from a timestamp
- State management lives in `lib/presentation/providers/` (Riverpod)
- Never commit production Firebase credentials — use environment-specific projects
- Keep `google-services.json` and `GoogleService-Info.plist` out of public repos

---

## 🗄️ Database Schema

| Hive Box | Model | Purpose |
| :--- | :--- | :--- |
| `products` | `Product` | Master catalog with variant stock |
| `sales` | `Sale` | Invoice and transaction records |
| `inventory_movements` | `InventoryMovement` | Immutable audit log of stock changes |
| `customers` | `Customer` | CRM profiles and ledger |
| `sync_queue` | `SyncQueueItem` | Pending cloud sync operations |
| `sync_logs` | `SyncLogModel` | Outcome of each cloud exchange |
| `history` | `ActionHistory` | Business activity trail, shown in History |
| `diagnostic_logs` | `DiagnosticLog` | Local failures in money and stock paths; device-only, never synced |
| `checkout_journal` | *(untyped)* | In-flight sales, so an interrupted checkout can be reversed at startup |

> **In-Memory Index:** `_barcodeIndex` — a `Map<String, Product>` rebuilt on startup for O(1) barcode lookups.
---

<p align="center">
  Built with 💙 and Flutter
</p>
