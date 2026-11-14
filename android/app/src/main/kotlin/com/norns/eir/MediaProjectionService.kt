package com.norns.eir

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
import androidx.core.app.NotificationCompat

/**
 * Foreground Service for Android MediaProjection.
 * Required by Android 10+ and strictly enforced on Android 14+ (API 34+)
 * before invoking MediaProjectionManager.getMediaProjection().
 */
class MediaProjectionService : Service() {
    companion object {
        const val CHANNEL_ID = "eir_media_projection_channel"
        const val NOTIFICATION_ID = 1002
        const val CHAT_CHANNEL_ID = "eir_screen_share_chat_channel"
        const val CHAT_NOTIFICATION_ID = 1003
        const val KEY_TEXT_REPLY = "key_text_reply"
        const val ACTION_REPLY = "com.norns.eir.ACTION_REPLY"

        fun start(context: Context) {
            val intent = Intent(context, MediaProjectionService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, MediaProjectionService::class.java)
            context.stopService(intent)
        }

        fun showChatMessageNotification(context: Context, id: String, sender: String, text: String) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHAT_CHANNEL_ID,
                    "Eir 投屏互动消息",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "投屏推流时接收观众弹幕与即时消息通知"
                    enableVibration(true)
                    setShowBadge(true)
                }
                manager.createNotificationChannel(channel)
            }

            val remoteInput = androidx.core.app.RemoteInput.Builder(KEY_TEXT_REPLY)
                .setLabel("快捷回复...")
                .build()

            val replyIntent = Intent(context, ScreenShareReplyReceiver::class.java).apply {
                action = ACTION_REPLY
                putExtra("messageId", id)
            }

            val replyPendingIntent = PendingIntent.getBroadcast(
                context,
                id.hashCode(),
                replyIntent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
            )

            val replyAction = NotificationCompat.Action.Builder(
                R.mipmap.ic_launcher,
                "回复",
                replyPendingIntent
            ).addRemoteInput(remoteInput).build()

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val contentPendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            val notification = NotificationCompat.Builder(context, CHAT_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("观众 [$sender]")
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setAutoCancel(true)
                .setContentIntent(contentPendingIntent)
                .addAction(replyAction)
                .build()

            manager.notify(CHAT_NOTIFICATION_ID, notification)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Eir 屏幕投屏服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "投屏推流时保持后台屏幕画面与伴音捕获"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Eir 正在实时投屏")
            .setContentText("正在实时捕获屏幕画面与伴音传输至远端")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
