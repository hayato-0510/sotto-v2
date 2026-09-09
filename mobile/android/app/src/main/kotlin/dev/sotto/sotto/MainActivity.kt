package dev.sotto.sotto

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter と BLE の境界（設計書 §7.1「自作のプラットフォームチャネル」）。
 *
 * 口は次のとおり。増やす前に設計書 §7.2 を読む。
 *   受け手：startDemand(blob) / stopDemand() / demandReply(json) / demandRelease()
 *   譲る側：startScan() / stopScan() / connect(id) → blob / write(json) / disconnect()
 *   共通　：requestPermissions() → bool / isBluetoothOn() → bool
 *
 * イベント（EventChannel）：
 *   {type:"scan", id, token, rssi} / {type:"message", json} / {type:"advertising", on}
 *   {type:"disconnected"} / {type:"error", message}
 */
class MainActivity : FlutterActivity() {
    private var sink: EventChannel.EventSink? = null
    private var peripheral: DemandPeripheral? = null
    private var central: GiverCentral? = null
    private var permissionResult: MethodChannel.Result? = null

    private val emit: (Map<String, Any?>) -> Unit = { event -> sink?.success(event) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        peripheral = DemandPeripheral(applicationContext, emit)
        central = GiverCentral(applicationContext, emit)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, Gatt.EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
                override fun onCancel(arguments: Any?) { sink = null }
            },
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, Gatt.METHOD_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "requestPermissions" -> requestPermissions(result)
                    "isBluetoothOn" -> result.success(isBluetoothOn())

                    "startDemand" -> {
                        val blob = call.argument<String>("blob") ?: return@setMethodCallHandler result.error("arg", "blob が必要です", null)
                        if (!isBluetoothOn()) return@setMethodCallHandler result.error("bt_off", "Bluetooth がオフです", null)
                        DemandService.start(this)
                        peripheral?.start(blob)
                        result.success(null)
                    }
                    "stopDemand" -> {
                        peripheral?.stop()
                        DemandService.stop(this)
                        result.success(null)
                    }
                    "demandReply" -> {
                        peripheral?.reply(call.argument<String>("json") ?: "")
                        result.success(null)
                    }
                    "demandRelease" -> {
                        peripheral?.release()
                        result.success(null)
                    }

                    "startScan" -> {
                        if (!isBluetoothOn()) return@setMethodCallHandler result.error("bt_off", "Bluetooth がオフです", null)
                        central?.startScan()
                        result.success(null)
                    }
                    "stopScan" -> { central?.stopScan(); result.success(null) }
                    "connect" -> {
                        val id = call.argument<String>("id") ?: return@setMethodCallHandler result.error("arg", "id が必要です", null)
                        central?.connect(id) { r ->
                            r.fold({ result.success(it) }, { result.error("connect", it.message, null) })
                        }
                    }
                    "write" -> {
                        val json = call.argument<String>("json") ?: return@setMethodCallHandler result.error("arg", "json が必要です", null)
                        central?.write(json) { r ->
                            r.fold({ result.success(null) }, { result.error("write", it.message, null) })
                        }
                    }
                    "disconnect" -> { central?.disconnect(); result.success(null) }

                    else -> result.notImplemented()
                }
            } catch (e: SecurityException) {
                result.error("permission", "Bluetooth の権限がありません", null)
            } catch (e: Exception) {
                result.error("ble", e.message, null)
            }
        }
    }

    private fun isBluetoothOn(): Boolean {
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        return manager.adapter?.isEnabled == true
    }

    private fun requiredPermissions(): List<String> {
        val list = mutableListOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT,
        )
        if (Build.VERSION.SDK_INT >= 33) list.add(Manifest.permission.POST_NOTIFICATIONS)
        return list
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val missing = requiredPermissions().filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), 7)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 7) return
        val r = permissionResult ?: return
        permissionResult = null
        // 通知権限は発信の継続に必須ではない。BLE の3つが揃っていれば可とする
        val bleGranted = requiredPermissions()
            .filter { it != Manifest.permission.POST_NOTIFICATIONS }
            .all { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }
        r.success(bleGranted)
    }

    override fun onDestroy() {
        central?.stopScan()
        central?.disconnect()
        super.onDestroy()
    }
}
