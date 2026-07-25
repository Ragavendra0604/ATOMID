<p align="center">
  <img src="assets/images/logo.jpeg" alt="Atomid Logo" width="120" style="border-radius: 20px;" />
</p>

<h1 align="center">Atomid</h1>

<p align="center">
  <strong>⚡ Offline-first retail & POS platform — built with Flutter</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.12-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.12-0175C2?logo=dart&logoColor=white" alt="Dart" />
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
| 🔄 **Offline-First Sync** | Hive local storage → automatic Firestore sync with exponential backoff retry |
| 🔐 **RBAC** | Role-based access control — Owner (full access) and Staff (granular permissions) |
| 📊 **Dashboard & Reports** | Revenue analytics, low-stock alerts, and transaction history |
| 🧾 **PDF Export** | Generate and print invoices, reports, and barcode sheets |
| 📱 **Multi-Platform** | Android · iOS · Web · Windows · macOS · Linux |

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
├── core/                    # App-wide utilities
│   ├── services/            # RBAC, Export services
│   ├── theme/               # Light / Dark mode config
│   └── utils/               # Responsive layout builders
├── data/
│   ├── models/              # Hive entities (Product, Sale, Customer …)
│   └── repositories/        # StorageRepository, FirebaseRepository
├── domain/
│   └── services/            # AuthService, SyncService, CustomerService
├── presentation/
│   ├── features/            # Feature modules (billing, products, inventory …)
│   ├── providers/           # Riverpod state providers
│   ├── screens/             # Root-level screens
│   └── widgets/             # Shared components (AppShell, guards)
├── main.dart                # App entry point
└── firebase_options.dart    # Multi-platform Firebase config
```

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) `^3.12`
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
| **Android** | Place `google-services.json` in `android/app/` |
| **iOS / macOS** | Add `GoogleService-Info.plist` to the Xcode target |
| **All** | Update or regenerate `lib/firebase_options.dart` if switching Firebase projects |

### Run

```bash
flutter run
```

### Build for Production

```bash
flutter build apk --release          # Android APK
flutter build appbundle --release     # Android App Bundle
flutter build ipa --release           # iOS (macOS host required)
flutter build web --release           # Web
flutter build windows --release       # Windows
flutter build macos --release         # macOS
flutter build linux --release         # Linux
```

---

## 🔄 Offline Sync Architecture

Atomid guarantees full operation without internet. All mutations are queued locally and synced when connectivity is restored.

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
                                           │  (10 items / batch)   │
                                           └───────────┬───────────┘
                                                       │
                                             ┌─────────┴─────────┐
                                             │                   │
                                       ✅ Success           ❌ Failure
                                       (Remove from         (Exponential backoff
                                          queue)               retry — max 5)
```

---

## 🔐 Authentication & Authorization

### Auth Flow

```
App Start → Session Check → Valid? → Dashboard
                         → Invalid? → Login Screen → Firebase Auth → Dashboard
```

### Role-Based Access

| Role | Access Level |
| :--- | :--- |
| **Owner** | Full access — bypasses all permission checks |
| **Staff** | Granular permissions defined per employee |

Access is enforced via `RbacService` and the `RoleGuardWidget` wrapper at the UI level.

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
- `test/unit/` — Model and service tests
- `test/widget/` — UI component tests

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
| `activity_logs` | `ActivityLogModel` | System action tracking |

> **In-Memory Index:** `_barcodeIndex` — a `Map<String, Product>` rebuilt on startup for O(1) barcode lookups.
---

<p align="center">
  Built with 💙 and Flutter
</p>
