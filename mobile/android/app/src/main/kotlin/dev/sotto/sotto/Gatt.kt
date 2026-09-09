package dev.sotto.sotto

import java.util.UUID

/**
 * BLE の契約。Dart 側（mobile/lib/ble.dart）とメッセージの形を揃える。
 *
 * 電波に載せるのは「需要モードの利用者がいる」（サービス UUID）と、更新されるトークン（4バイト）だけ
 * （設計書 §1.4 ペイロード最小）。需要の中身は封緘（サーバ鍵で暗号化）されたまま GATT で渡す。
 *
 * 特性：
 *   DEMAND  read   受け手 → 譲る側  封緘された需要（base64url 文字列）
 *   INBOX   write  譲る側 → 受け手  {"type":"offer","handoff":{...}} / {"type":"cancel"}
 *   OUTBOX  notify 受け手 → 譲る側  {"type":"thanks"} / {"type":"not_found"} / {"type":"taken"}
 *
 * 【実機未検証】RSSI 閾値・送信出力・トークン更新間隔は、スパイク（docs/スパイク手順書.md）が
 * 実機不在で未実施のため暫定値である。docs/spike-results.md に結果が出たら差し替える。
 */
object Gatt {
    val SERVICE_UUID: UUID = UUID.fromString("6f747473-0001-4c45-b1e0-5b4c45000001")
    val DEMAND_UUID: UUID = UUID.fromString("6f747473-0002-4c45-b1e0-5b4c45000001")
    val INBOX_UUID: UUID = UUID.fromString("6f747473-0003-4c45-b1e0-5b4c45000001")
    val OUTBOX_UUID: UUID = UUID.fromString("6f747473-0004-4c45-b1e0-5b4c45000001")
    val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    /** トークンの更新間隔。設計書 §1.4「15分程度」 */
    const val TOKEN_ROTATION_MS = 15L * 60L * 1000L

    /** 譲る側が「すぐ近く」とみなす RSSI（dBm）。暫定値。スパイク1で確定する */
    const val NEAR_RSSI_DBM = -75

    /** 譲る側が要求する MTU。封緘（〜400バイト）と Handoff の JSON を1パケットで渡すため */
    const val MTU = 512

    const val METHOD_CHANNEL = "dev.sotto/ble"
    const val EVENT_CHANNEL = "dev.sotto/ble/events"
}
