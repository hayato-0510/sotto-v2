package dev.sotto.sotto

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log

/**
 * 譲る側：スキャン ＋ GATT クライアント。
 *
 * 譲る側はアプリを開いている間だけスキャンする（プル型、設計書 §2.2）。背景スキャンはしない。
 * ［ 譲る ］で相手に接続し、封緘された需要を読み、Handoff を書き込み、返事（お礼など）を通知で受ける。
 */
@SuppressLint("MissingPermission")
class GiverCentral(private val context: Context, private val emit: (Map<String, Any?>) -> Unit) {
    private val tag = "SottoCentral"
    private val main = Handler(Looper.getMainLooper())
    private val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter get() = manager.adapter

    private var scanner: BluetoothLeScanner? = null
    private var scanning = false
    private val seen = HashMap<String, BluetoothDevice>()

    private var gatt: BluetoothGatt? = null
    private var inbox: BluetoothGattCharacteristic? = null
    private var demand: BluetoothGattCharacteristic? = null
    private var onConnected: ((Result<String>) -> Unit)? = null
    private var onWritten: ((Result<Unit>) -> Unit)? = null

    // ── スキャン ─────────────────────────────────────

    fun startScan() {
        if (scanning) return
        val s = adapter?.bluetoothLeScanner ?: run {
            emit(mapOf("type" to "error", "message" to "Bluetooth がオフのようです"))
            return
        }
        scanner = s
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(Gatt.SERVICE_UUID)).build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .build()
        s.startScan(listOf(filter), settings, scanCallback)
        scanning = true
    }

    fun stopScan() {
        if (!scanning) return
        try { scanner?.stopScan(scanCallback) } catch (e: Exception) { Log.w(tag, "stopScan", e) }
        scanning = false
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            seen[device.address] = device
            val token = result.scanRecord?.getServiceData(ParcelUuid(Gatt.SERVICE_UUID))
            val tokenHex = token?.joinToString("") { String.format("%02x", it) } ?: ""
            main.post {
                emit(mapOf("type" to "scan", "id" to device.address, "token" to tokenHex, "rssi" to result.rssi))
            }
        }

        override fun onScanFailed(errorCode: Int) {
            scanning = false
            main.post { emit(mapOf("type" to "error", "message" to "スキャンを開始できませんでした（コード $errorCode）")) }
        }
    }

    // ── 接続と受け渡し ───────────────────────────────

    /** 接続して封緘された需要を読む。完了時に blob を返す */
    fun connect(id: String, callback: (Result<String>) -> Unit) {
        disconnect()
        val device = seen[id] ?: adapter?.getRemoteDevice(id)
        if (device == null) {
            callback(Result.failure(IllegalStateException("相手の端末が見つかりません")))
            return
        }
        onConnected = callback
        gatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        main.postDelayed(connectTimeout, 10_000)
    }

    private val connectTimeout = Runnable {
        val cb = onConnected ?: return@Runnable
        onConnected = null
        disconnect()
        cb(Result.failure(IllegalStateException("相手の端末に接続できませんでした")))
    }

    /** INBOX に JSON を書き込む（offer / cancel） */
    fun write(json: String, callback: (Result<Unit>) -> Unit) {
        val g = gatt
        val c = inbox
        if (g == null || c == null) {
            callback(Result.failure(IllegalStateException("接続していません")))
            return
        }
        onWritten = callback
        val bytes = json.toByteArray(Charsets.UTF_8)
        val ok = if (Build.VERSION.SDK_INT >= 33) {
            g.writeCharacteristic(c, bytes, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            c.value = bytes
            c.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            @Suppress("DEPRECATION")
            g.writeCharacteristic(c)
        }
        if (!ok) {
            onWritten = null
            callback(Result.failure(IllegalStateException("書き込みを開始できませんでした")))
        }
    }

    fun disconnect() {
        main.removeCallbacks(connectTimeout)
        try { gatt?.disconnect() } catch (_: Exception) {}
        try { gatt?.close() } catch (_: Exception) {}
        gatt = null
        inbox = null
        demand = null
    }

    private fun fail(message: String) {
        val cb = onConnected
        onConnected = null
        main.removeCallbacks(connectTimeout)
        disconnect()
        main.post { cb?.invoke(Result.failure(IllegalStateException(message))) }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                g.requestMtu(Gatt.MTU)
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                if (onConnected != null) {
                    fail("相手の端末との接続が切れました")
                } else {
                    main.post { emit(mapOf("type" to "disconnected")) }
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            g.discoverServices()
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            val service = g.getService(Gatt.SERVICE_UUID) ?: return fail("相手の端末に Sotto のサービスがありません")
            demand = service.getCharacteristic(Gatt.DEMAND_UUID)
            inbox = service.getCharacteristic(Gatt.INBOX_UUID)
            val outbox = service.getCharacteristic(Gatt.OUTBOX_UUID)
            if (demand == null || inbox == null || outbox == null) return fail("相手の端末の特性が揃っていません")
            g.setCharacteristicNotification(outbox, true)
            val cccd = outbox.getDescriptor(Gatt.CCCD_UUID) ?: return fail("通知の設定ができません")
            if (Build.VERSION.SDK_INT >= 33) {
                g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
            } else {
                @Suppress("DEPRECATION")
                cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                @Suppress("DEPRECATION")
                g.writeDescriptor(cccd)
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            val d = demand ?: return fail("需要の特性がありません")
            @Suppress("DEPRECATION")
            g.readCharacteristic(d)
        }

        private fun deliverRead(uuid: java.util.UUID, value: ByteArray) {
            if (uuid != Gatt.DEMAND_UUID) return
            val cb = onConnected ?: return
            onConnected = null
            main.removeCallbacks(connectTimeout)
            val blob = String(value, Charsets.UTF_8)
            main.post { cb(Result.success(blob)) }
        }

        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) return fail("需要を読み取れませんでした")
            deliverRead(c.uuid, value)
        }

        @Deprecated("Deprecated in Java")
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT >= 33) return
            if (status != BluetoothGatt.GATT_SUCCESS) return fail("需要を読み取れませんでした")
            @Suppress("DEPRECATION")
            deliverRead(c.uuid, c.value ?: ByteArray(0))
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            val cb = onWritten ?: return
            onWritten = null
            main.post {
                if (status == BluetoothGatt.GATT_SUCCESS) cb(Result.success(Unit))
                else cb(Result.failure(IllegalStateException("書き込みに失敗しました（$status）")))
            }
        }

        private fun deliverChanged(value: ByteArray) {
            val json = String(value, Charsets.UTF_8)
            main.post { emit(mapOf("type" to "message", "json" to json)) }
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            deliverChanged(value)
        }

        @Deprecated("Deprecated in Java")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT >= 33) return
            @Suppress("DEPRECATION")
            deliverChanged(c.value ?: ByteArray(0))
        }
    }
}
