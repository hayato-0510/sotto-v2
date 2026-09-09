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
 *
 * スレッド：GATT のコールバックは binder スレッドで届くので、状態を触る処理はすべて main へ寄せる。
 * 保留中のコールバック（onConnected / onWritten）は必ず1回だけ解決する。
 * 切断・タイムアウト・disconnect() のどれで終わっても、待っている側を放置しない。
 */
@SuppressLint("MissingPermission")
class GiverCentral(private val context: Context, private val emit: (Map<String, Any?>) -> Unit) {
    private val tag = "SottoCentral"
    private val main = Handler(Looper.getMainLooper())
    private val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter get() = manager.adapter
    private val serviceUuid = ParcelUuid(Gatt.SERVICE_UUID)

    private var scanner: BluetoothLeScanner? = null
    private var scanning = false
    private val seen = HashMap<String, BluetoothDevice>()

    // 以下はすべて main スレッドでのみ触る
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
        val filter = ScanFilter.Builder().setServiceUuid(serviceUuid).build()
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
            val rssi = result.rssi
            main.post {
                seen[device.address] = device
                emit(mapOf("type" to "scan", "id" to device.address, "rssi" to rssi))
            }
        }

        override fun onScanFailed(errorCode: Int) {
            main.post {
                scanning = false
                emit(mapOf("type" to "error", "message" to "スキャンを開始できませんでした（コード $errorCode）"))
            }
        }
    }

    // ── 接続と受け渡し ───────────────────────────────

    /** 接続して封緘された需要を読む。完了時に blob を返す。10秒で諦める */
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

    private val connectTimeout = Runnable { failConnect("相手の端末に接続できませんでした") }

    /** INBOX に JSON を書き込む（offer / cancel）。5秒で諦める */
    fun write(json: String, callback: (Result<Unit>) -> Unit) {
        val g = gatt
        val c = inbox
        if (g == null || c == null) {
            callback(Result.failure(IllegalStateException("接続していません")))
            return
        }
        settleWrite(Result.failure(IllegalStateException("前の書き込みが完了していません")))
        onWritten = callback
        main.postDelayed(writeTimeout, 5_000)
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
        if (!ok) settleWrite(Result.failure(IllegalStateException("書き込みを開始できませんでした")))
    }

    private val writeTimeout = Runnable { settleWrite(Result.failure(IllegalStateException("書き込みの応答がありません"))) }

    /** 接続を閉じる。待っているコールバックがあれば失敗として解決する */
    fun disconnect() {
        main.removeCallbacks(connectTimeout)
        val pendingConnect = onConnected
        onConnected = null
        settleWrite(Result.failure(IllegalStateException("接続を閉じました")))
        try { gatt?.disconnect() } catch (_: Exception) {}
        try { gatt?.close() } catch (_: Exception) {}
        gatt = null
        inbox = null
        demand = null
        pendingConnect?.invoke(Result.failure(IllegalStateException("接続を閉じました")))
    }

    /** onConnected を1回だけ解決する（main スレッド） */
    private fun settleConnect(result: Result<String>) {
        main.removeCallbacks(connectTimeout)
        val cb = onConnected ?: return
        onConnected = null
        cb(result)
    }

    /** onWritten を1回だけ解決する（main スレッド） */
    private fun settleWrite(result: Result<Unit>) {
        main.removeCallbacks(writeTimeout)
        val cb = onWritten ?: return
        onWritten = null
        cb(result)
    }

    private fun failConnect(message: String) {
        if (onConnected == null) return
        val cb = onConnected
        onConnected = null
        main.removeCallbacks(connectTimeout)
        try { gatt?.disconnect() } catch (_: Exception) {}
        try { gatt?.close() } catch (_: Exception) {}
        gatt = null
        inbox = null
        demand = null
        cb?.invoke(Result.failure(IllegalStateException(message)))
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                g.requestMtu(Gatt.MTU)
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                main.post {
                    if (g !== gatt) return@post
                    if (onConnected != null) {
                        failConnect("相手の端末との接続が切れました")
                    } else {
                        settleWrite(Result.failure(IllegalStateException("相手の端末との接続が切れました")))
                        emit(mapOf("type" to "disconnected"))
                    }
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            g.discoverServices()
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            main.post {
                if (g !== gatt) return@post
                val service = g.getService(Gatt.SERVICE_UUID)
                    ?: return@post failConnect("相手の端末に Sotto のサービスがありません")
                demand = service.getCharacteristic(Gatt.DEMAND_UUID)
                inbox = service.getCharacteristic(Gatt.INBOX_UUID)
                val outbox = service.getCharacteristic(Gatt.OUTBOX_UUID)
                if (demand == null || inbox == null || outbox == null) {
                    return@post failConnect("相手の端末の特性が揃っていません")
                }
                g.setCharacteristicNotification(outbox, true)
                val cccd = outbox.getDescriptor(Gatt.CCCD_UUID) ?: return@post failConnect("通知の設定ができません")
                if (Build.VERSION.SDK_INT >= 33) {
                    g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                } else {
                    @Suppress("DEPRECATION")
                    cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    @Suppress("DEPRECATION")
                    g.writeDescriptor(cccd)
                }
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            main.post {
                if (g !== gatt) return@post
                val d = demand ?: return@post failConnect("需要の特性がありません")
                @Suppress("DEPRECATION")
                g.readCharacteristic(d)
            }
        }

        private fun deliverRead(g: BluetoothGatt, uuid: java.util.UUID, value: ByteArray, status: Int) {
            if (uuid != Gatt.DEMAND_UUID) return
            val blob = String(value, Charsets.UTF_8)
            main.post {
                if (g !== gatt) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) failConnect("需要を読み取れませんでした")
                else settleConnect(Result.success(blob))
            }
        }

        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            deliverRead(g, c.uuid, value, status)
        }

        @Deprecated("Deprecated in Java")
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT >= 33) return
            @Suppress("DEPRECATION")
            deliverRead(g, c.uuid, c.value ?: ByteArray(0), status)
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            main.post {
                if (g !== gatt) return@post
                if (status == BluetoothGatt.GATT_SUCCESS) settleWrite(Result.success(Unit))
                else settleWrite(Result.failure(IllegalStateException("書き込みに失敗しました（$status）")))
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
