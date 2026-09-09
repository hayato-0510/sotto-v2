# Sotto アプリ（Flutter ＋ Kotlin BLE、Android のみ）

設計は [`../docs/設計書.md`](../docs/設計書.md)。文言は §3.3、暫定値は §7.2.1。開発時の前提は [`../AGENTS.md`](../AGENTS.md)。

## 構成

| 場所 | 役割 |
| :--- | :--- |
| `lib/screens/role.dart` | 起動・役割選択。同一OS制約とデモ制約の明示 |
| `lib/screens/receiver.dart` | 受け手：需要の宣言 → 確認 → 発信 → 申し出の受信 → お礼 |
| `lib/screens/giver.dart` | 譲る側：スキャン → 混み具合 → 譲る → 動作 → お礼が届く |
| `lib/screens/comparison.dart` | 審査用の混雑度対比。`assets/comparison.json` を読むだけ |
| `lib/ble.dart` | 自作チャネルの Dart 側。端末間メッセージの形もここ |
| `lib/api.dart` `lib/types.dart` | AI サーバの呼び出しと契約（`../lib/contracts.ts` と揃える） |
| `lib/ui.dart` | 引き算のルール（設計書 §3）を縛る最小の部品 |
| `android/…/kotlin/dev/sotto/sotto/` | `Gatt.kt`（契約）／`DemandPeripheral.kt`（発信＋GATTサーバ）／`GiverCentral.kt`（スキャン＋GATTクライアント）／`DemandService.kt`（常駐）／`MainActivity.kt`（チャネルの口と権限） |

## ビルド

```bash
flutter pub get
flutter analyze && flutter test
flutter build apk --release --dart-define=SOTTO_API_BASE=https://<AIサーバのURL>
```

`SOTTO_API_BASE` を省くと `lib/api.dart` の既定値になる。APK は `build/app/outputs/flutter-apk/app-release.apk`。

## 実機での確認

Android 12 以上の実機2台。エミュレータでは BLE が動かない。手順は [`../docs/手動確認.md`](../docs/手動確認.md)。
**近接検知は実機で一度も検証していない**（RSSI 閾値・送信出力は暫定）。
