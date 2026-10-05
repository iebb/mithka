package ad.neko.mithka

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * A started, same-process foreground service that hosts the music media
 * notification while playback is active.
 *
 * The notification itself is built by [NowPlayingPlugin] and re-posted on
 * every state change; this service only promotes it to a foreground one so
 * Android keeps the process (and with it flutter_sound's MediaPlayer) alive
 * while the app is backgrounded. It is stopped when playback is cleared.
 */
class MediaPlaybackService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = NowPlayingPlugin.lastNotification
        if (notification == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NowPlayingPlugin.NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NowPlayingPlugin.NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    companion object {
        fun start(context: Context) {
            val intent = Intent(context, MediaPlaybackService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MediaPlaybackService::class.java))
        }
    }
}
