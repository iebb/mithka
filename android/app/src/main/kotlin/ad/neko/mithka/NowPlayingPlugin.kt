package ad.neko.mithka

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.SystemClock
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.media.app.NotificationCompat.MediaStyle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Publishes the in-app music player to the system media controls: the media
 * notification, the quick-settings player and the lock screen.
 *
 * flutter_sound plays through a bare MediaPlayer with no MediaSession, so the
 * system has nothing to show. Dart owns the queue and playback; this class
 * only mirrors its state and forwards remote commands back over the channel.
 */
class NowPlayingPlugin(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private var session: MediaSessionCompat? = null
    private var artworkPath: String? = null
    private var artwork: Bitmap? = null

    init {
        channel.setMethodCallHandler(this)
        active = this
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "update" -> {
                update(call)
                result.success(null)
            }
            "clear" -> {
                clear()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        clear()
        session?.release()
        session = null
        channel.setMethodCallHandler(null)
        if (active === this) active = null
    }

    private fun send(method: String, arguments: Any? = null) {
        channel.invokeMethod(method, arguments)
    }

    private fun ensureSession(): MediaSessionCompat {
        session?.let { return it }
        val created = MediaSessionCompat(appContext, "MithkaMusic").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() = send("play")
                override fun onPause() = send("pause")
                override fun onSkipToNext() = send("next")
                override fun onSkipToPrevious() = send("previous")
                override fun onSeekTo(pos: Long) = send("seek", pos.toInt())
                override fun onStop() = send("stop")
            })
            launchIntent()?.let { setSessionActivity(it) }
        }
        session = created
        return created
    }

    private fun update(call: MethodCall) {
        val title = call.argument<String>("title").orEmpty()
        val artist = call.argument<String>("artist").orEmpty()
        val album = call.argument<String>("album").orEmpty()
        val durationMs = call.argument<Number>("durationMs")?.toLong() ?: 0L
        val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
        val playing = call.argument<Boolean>("playing") ?: false
        val labels = call.argument<Map<String, String>>("labels").orEmpty()
        val cover = loadArtwork(call.argument<String>("artworkPath"))

        val mediaSession = ensureSession()
        mediaSession.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
                .apply {
                    if (cover != null) {
                        putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, cover)
                    }
                }
                .build(),
        )
        mediaSession.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(SESSION_ACTIONS)
                .setState(
                    if (playing) {
                        PlaybackStateCompat.STATE_PLAYING
                    } else {
                        PlaybackStateCompat.STATE_PAUSED
                    },
                    positionMs.coerceAtLeast(0L),
                    if (playing) 1f else 0f,
                    SystemClock.elapsedRealtime(),
                )
                .build(),
        )
        mediaSession.isActive = true
        postNotification(mediaSession, title, artist, cover, playing, labels)
    }

    private fun postNotification(
        mediaSession: MediaSessionCompat,
        title: String,
        artist: String,
        cover: Bitmap?,
        playing: Boolean,
        labels: Map<String, String>,
    ) {
        // MediaStyle notifications tied to a session are exempt from the
        // Android 13 notification permission, so post even when it is off.
        val manager = NotificationManagerCompat.from(appContext)
        ensureNotificationChannel(labels["channel"].orEmpty())
        val builder = NotificationCompat.Builder(appContext, NOTIFICATION_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_music)
            .setContentTitle(title)
            .setContentText(artist)
            .setLargeIcon(cover)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setSilent(true)
            .setOngoing(playing)
            .setDeleteIntent(actionIntent(ACTION_STOP))
            .addAction(
                android.R.drawable.ic_media_previous,
                labels["previous"] ?: "Previous",
                actionIntent(ACTION_PREVIOUS),
            )
            .addAction(
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) labels["pause"] ?: "Pause" else labels["play"] ?: "Play",
                actionIntent(if (playing) ACTION_PAUSE else ACTION_PLAY),
            )
            .addAction(
                android.R.drawable.ic_media_next,
                labels["next"] ?: "Next",
                actionIntent(ACTION_NEXT),
            )
            .setStyle(
                MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2),
            )
        launchIntent()?.let { builder.setContentIntent(it) }
        try {
            manager.notify(NOTIFICATION_ID, builder.build())
        } catch (_: SecurityException) {
            // Notification permission revoked; the session still serves
            // headset buttons and Bluetooth controls.
        }
    }

    private fun clear() {
        NotificationManagerCompat.from(appContext).cancel(NOTIFICATION_ID)
        session?.let {
            it.setPlaybackState(
                PlaybackStateCompat.Builder()
                    .setState(PlaybackStateCompat.STATE_STOPPED, 0L, 0f)
                    .build(),
            )
            it.isActive = false
        }
        artworkPath = null
        artwork = null
    }

    private fun ensureNotificationChannel(name: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = appContext.getSystemService(NotificationManager::class.java) ?: return
        val label = name.ifBlank { "Music" }
        val existing = manager.getNotificationChannel(NOTIFICATION_CHANNEL)
        if (existing != null && existing.name == label) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL,
            label,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            setShowBadge(false)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun loadArtwork(path: String?): Bitmap? {
        if (path.isNullOrEmpty()) {
            artworkPath = null
            artwork = null
            return null
        }
        if (path == artworkPath) return artwork
        artworkPath = path
        artwork = try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= ARTWORK_SIZE &&
                bounds.outHeight / (sample * 2) >= ARTWORK_SIZE
            ) {
                sample *= 2
            }
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
        } catch (_: Exception) {
            null
        }
        return artwork
    }

    private fun launchIntent(): PendingIntent? {
        val intent = appContext.packageManager
            .getLaunchIntentForPackage(appContext.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            ?: return null
        return PendingIntent.getActivity(
            appContext,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun actionIntent(action: String): PendingIntent {
        val intent = Intent(appContext, NowPlayingActionReceiver::class.java).setAction(action)
        return PendingIntent.getBroadcast(
            appContext,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    internal fun handleAction(action: String?) {
        when (action) {
            ACTION_PLAY -> send("play")
            ACTION_PAUSE -> send("pause")
            ACTION_NEXT -> send("next")
            ACTION_PREVIOUS -> send("previous")
            ACTION_STOP -> send("stop")
        }
    }

    companion object {
        const val CHANNEL = "mithka/now_playing"
        private const val NOTIFICATION_CHANNEL = "mithka_music_playback"
        private const val NOTIFICATION_ID = 0x6d757369
        private const val ARTWORK_SIZE = 512
        private const val SESSION_ACTIONS =
            PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_SEEK_TO or
                PlaybackStateCompat.ACTION_STOP
        internal const val ACTION_PLAY = "ad.neko.mithka.music.PLAY"
        internal const val ACTION_PAUSE = "ad.neko.mithka.music.PAUSE"
        internal const val ACTION_NEXT = "ad.neko.mithka.music.NEXT"
        internal const val ACTION_PREVIOUS = "ad.neko.mithka.music.PREVIOUS"
        internal const val ACTION_STOP = "ad.neko.mithka.music.STOP"

        @Volatile
        internal var active: NowPlayingPlugin? = null
    }
}

/** Routes media notification buttons to the live player bridge. */
class NowPlayingActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        NowPlayingPlugin.active?.handleAction(intent.action)
    }
}
