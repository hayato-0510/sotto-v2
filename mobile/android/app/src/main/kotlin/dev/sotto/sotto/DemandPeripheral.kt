package dev.sotto.sotto

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import java.security.SecureRandom

/**
 * 受け手側：発信（advertising）＋ GATT サーバ。
 *
 * 排他制御（設計書 §2.6）：［ 譲る ］の書き込みは先着1件だけを受け付ける。
 * 2件目には OUTBOX で {"type":"taken"} を返し、状態を動かさない。
 *
 * モーションゲート（設計書 §1.4）は**未実装**。需要が有効な間は常に発信する。
 * 画面にもその旨を出す（AGENTS.md §5）。
 */
@SuppressLint("MissingPermission")
class DemandPeripheral(private val context: Context, private val emit: (Map<String, Any?>) -> Unit) {
    private val tag = "SottoPeripheral"
    private val main = Handler(Looper.getMainLooper())
    private val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter get() = manager.adapter

    private var advertiser: BluetoothLeAdvertiser? = null
    private var server: BluetoothGattServer? = null
    private var outbox: BluetoothGattCharacteristic? = null
    private var blobBytes: ByteArray = ByteArray(0)
    private var running = false

    /** 通知を購読している譲る側の端末 */
    private val subscribers = LinkedHashSet<BluetoothDevice>()

    /** 先着で［ 譲る ］を書き込んだ端末。null なら未提示 */
    private var offerer: BluetoothDevice? = null

    /** 分割書き込み（prepared write）の一時バッファ */
    private val pending = HashMap<String, java.io.ByteArrayOutputStream>()

    val isRunning get() = running

    fun start(blob: String) {
        if (running) stop()
        blobBytes = blob.toByteArray(Charsets.UTF_8)
        running = true
        offerer = null
        openServer()
        startAdvertising()
        main.postDelayed(rotate, Gatt.TOKEN_ROTATION_MS)
        emit(mapOf("type" to "advertising", "on" to true))
    }

    fun stop() {
        running = false
        main.removeCallbacks(rotate)
        try { advertiser?.stopAdvertising(advertiseCallback) } catch (e: Exception) { Log.w(tag, "stopAdvertising", e) }
        advertiser = null
        try { server?.close() } catch (e: Exception) { Log.w(tag, "server.close", e) }
        server = null
        outbox = null
        subscribers.clear()
        offerer = null
        pending.clear()
        emit(mapOf("type" to "advertising", "on" to false))
    }

    /** 譲る側へ返事（thanks / not_found）。先着の端末にだけ届ける */
    fun reply(json: String) {
        val device = offerer ?: return
        notify(device, json)
    }

    /** 提示を解放する（お礼・見つからない・取り消し後）。次の［ 譲る ］を受けられる状態に戻す */
    fun release() {
        offerer = null
    }

    // ── 発信 ────────────────────────────────────────

    private val rotate = object : Runnable {
        override fun run() {
            if (!running) return
            try { advertiser?.stopAdvertising(advertiseCallback) } catch (_: Exception) {}
            startAdvertising()
            main.postDelayed(this, Gatt.TOKEN_ROTATION_MS)
        }
    }

    private fun newToken(): ByteArray = ByteArray(4).also { SecureRandom().nextBytes(it) }

    private fun startAdvertising() {
        val adv = adapter?.bluetoothLeAdvertiser
        if (adv == null) {
            emit(mapOf("type" to "error", "message" to "この端末は BLE の発信に対応していません"))
            return
        }
        advertiser = adv
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            // 【実機未検証】出力を絞って到達範囲を数mに限る案（スパイク手順書 §2 手順5）は未計測。
            // MEDIUM を暫定とし、譲る側の RSSI 閾値（Gatt.NEAR_RSSI_DBM）と組で調整する
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
            .setTimeout(0)
            .build()
        // 31バイトの制約：本体にはサービス UUID（18バイト）だけを載せ、トークンはスキャン応答に載せる
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addServiceUuid(ParcelUuid(Gatt.SERVICE_UUID))
            .build()
        val scanResponse = AdvertiseData.Builder()
            .addServiceData(ParcelUuid(Gatt.SERVICE_UUID), newToken())
            .build()
        adv.startAdvertising(settings, data, scanResponse, advertiseCallback)
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) {
            Log.w(tag, "advertise failed: $errorCode")
            main.post { emit(mapOf("type" to "error", "message" to "発信を開始できませんでした（コード $errorCode）")) }
        }
    }

    // ── GATT サーバ ──────────────────────────────────

    private fun openServer() {
        val s = manager.openGattServer(context, serverCallback) ?: run {
            emit(mapOf("type" to "error", "message" to "GATT サーバを開けませんでした"))
            return
        }
        val service = BluetoothGattService(Gatt.SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(
            BluetoothGattCharacteristic(
                Gatt.DEMAND_UUID,
                BluetoothGattCharacteristic.PROPERTY_READ,
                BluetoothGattCharacteristic.PERMISSION_READ,
            ),
        )
        service.addCharacteristic(
            BluetoothGattCharacteristic(
                Gatt.INBOX_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE,
                BluetoothGattCharacteristic.PERMISSION_WRITE,
            ),
        )
        val out = BluetoothGattCharacteristic(
            Gatt.OUTBOX_UUID,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ,
        )
        out.addDescriptor(
            BluetoothGattDescriptor(
                Gatt.CCCD_UUID,
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
            ),
        )
        service.addCharacteristic(out)
        outbox = out
        s.addService(service)
        server = s
    }

    private fun notify(device: BluetoothDevice, json: String) {
        val s = server ?: return
        val c = outbox ?: return
        val bytes = json.toByteArray(Charsets.UTF_8)
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                s.notifyCharacteristicChanged(device, c, false, bytes)
            } else {
                @Suppress("DEPRECATION")
                c.value = bytes
                @Suppress("DEPRECATION")
                s.notifyCharacteristicChanged(device, c, false)
            }
        } catch (e: Exception) {
            Log.w(tag, "notify", e)
        }
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothGatt.STATE_DISCONNECTED) {
                subscribers.remove(device)
                pending.remove(device.address)
                // 提示中の相手が切れた（アプリ終了・圏外）。取り消しと同じ扱いで探索へ戻す
                if (offerer != null && offerer?.address == device.address) {
                    offerer = null
                    main.post { emit(mapOf("type" to "message", "json" to "{\"type\":\"cancel\"}")) }
                }
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic,
        ) {
            val s = server ?: return
            val value = when (characteristic.uuid) {
                Gatt.DEMAND_UUID -> blobBytes
                else -> ByteArray(0)
            }
            if (offset > value.size) {
                s.sendResponse(device, requestId, BluetoothGatt.GATT_INVALID_OFFSET, offset, null)
                return
            }
            s.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value.copyOfRange(offset, value.size))
        }

        override fun onDescriptorReadRequest(
            device: BluetoothDevice, requestId: Int, offset: Int, descriptor: BluetoothGattDescriptor,
        ) {
            val v = if (subscribers.contains(device)) BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            else BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, v)
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?,
        ) {
            if (descriptor.uuid == Gatt.CCCD_UUID) {
                val enable = value != null && value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                if (enable) subscribers.add(device) else subscribers.remove(device)
            }
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?,
        ) {
            if (characteristic.uuid != Gatt.INBOX_UUID) {
                if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
                return
            }
            if (preparedWrite) {
                val buf = pending.getOrPut(device.address) { java.io.ByteArrayOutputStream() }
                if (value != null) buf.write(value)
                if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                return
            }
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            if (value != null) handleInbox(device, String(value, Charsets.UTF_8))
        }

        override fun onExecuteWrite(device: BluetoothDevice, requestId: Int, execute: Boolean) {
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            val buf = pending.remove(device.address) ?: return
            if (execute) handleInbox(device, String(buf.toByteArray(), Charsets.UTF_8))
        }
    }

    /** 譲る側からのメッセージ。先着1件の判定だけここで行い、中身は Dart に渡す */
    private fun handleInbox(device: BluetoothDevice, json: String) {
        val isOffer = json.contains("\"type\":\"offer\"") || json.contains("\"type\": \"offer\"")
        val current = offerer
        if (isOffer) {
            if (current != null && current.address != device.address) {
                // 2件目。状態は動かさず、その端末にだけ「他の方が譲りました」を返す
                notify(device, "{\"type\":\"taken\"}")
                return
            }
            offerer = device
        } else {
            // cancel 等は提示中の端末からしか受けない
            if (current == null || current.address != device.address) return
            offerer = null
        }
        main.post { emit(mapOf("type" to "message", "json" to json)) }
    }
}
