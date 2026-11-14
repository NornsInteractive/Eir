package com.norns.eir

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput

/**
 * Receiver handling direct replies from system notifications during active screen share.
 * Forwards typed reply to MainActivity which delivers it to Flutter WebRTC data channel.
 */
class ScreenShareReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val remoteInput = RemoteInput.getResultsFromIntent(intent)
        val replyText = remoteInput?.getCharSequence(MediaProjectionService.KEY_TEXT_REPLY)?.toString()
        if (!replyText.isNullOrBlank()) {
            MainActivity.onReplyFromNotification(replyText)

            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            val repliedNotification = NotificationCompat.Builder(context, MediaProjectionService.CHAT_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("已快捷回复")
                .setContentText(replyText)
                .setTimeoutAfter(3000)
                .build()
            manager?.notify(MediaProjectionService.CHAT_NOTIFICATION_ID, repliedNotification)
        }
    }
}
