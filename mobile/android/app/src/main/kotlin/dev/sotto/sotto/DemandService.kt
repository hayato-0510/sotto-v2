package dev.sotto.sotto

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * 受け手の発信を背景でも続けるための常駐サービス。
 *
 * Android は前景サービスに常駐通知を必須とする。この通知が「発信中であることを常に示す」
 * （設計書 §1.4、NFR-03）の役目を兼ねる。文言は待機画面（設計書 §3.3）と揃える。
 * 通知を消す＝発信を止める、ではない。停止はアプリの［ やめる ］から行う。
 */
class DemandService : Service() {
    companion object {
        const val CHANNEL_ID = "sotto_demand"
        const val NOTIFICATION_ID = 1

        fun start(context: Context) {
            val intent = Intent(context, DemandService::class.java)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DemandService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification: Notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("席がほしい、と発信中")
            .setContentText("見つかったら画面が変わります")
            .setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    private fun ensureChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(CHANNEL_ID, "発信中の表示", NotificationManager.IMPORTANCE_LOW)
        channel.description = "席がほしい、と発信している間だけ表示します"
        channel.setShowBadge(false)
        nm.createNotificationChannel(channel)
    }
}
