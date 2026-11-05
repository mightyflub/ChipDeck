// Foreground service that keeps ChipDeck playing with the screen off or the
// app in the background, with a media notification, lock screen and
// headphone/Bluetooth controls. Audio itself comes from libchipdeck.so
// (miniaudio on AAudio); this service only keeps the process alive and
// forwards button presses to Dart via MainActivity.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
package io.github.mightyflub.chipdeck

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.media.app.NotificationCompat.MediaStyle

class PlaybackService : Service() {
    private lateinit var session: MediaSessionCompat
    private var title = ""
    private var text = ""
    private var playing = false
    private var positionMs = 0L
    private var lengthMs = -1L // -1: unknown, no seek bar
    private var foreground = false

    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) onAction?.invoke("pause")
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Playback", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shows the tune that is playing"
                    setShowBadge(false)
                },
            )
        }
        session = MediaSessionCompat(this, "ChipDeck").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() { onAction?.invoke("play") }
                override fun onPause() { onAction?.invoke("pause") }
                override fun onSkipToNext() { onAction?.invoke("next") }
                override fun onSkipToPrevious() { onAction?.invoke("previous") }
                override fun onStop() { onAction?.invoke("stop") }
                override fun onSeekTo(pos: Long) { onAction?.invoke("seek:$pos") }
            })
            setSessionActivity(openAppIntent())
            isActive = true
        }
        ContextCompat.registerReceiver(
            this, noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (val action = intent?.getStringExtra(EXTRA_ACTION)) {
            null -> {}
            // Paused notification swiped away: just go away, keep the playlist.
            "dismiss" -> stopSelf()
            else -> onAction?.invoke(action)
        }
        intent?.getStringExtra(EXTRA_TITLE)?.let {
            apply(
                it, intent.getStringExtra(EXTRA_TEXT) ?: "", intent.getBooleanExtra(EXTRA_PLAYING, false),
                intent.getLongExtra(EXTRA_POSITION, 0L), intent.getLongExtra(EXTRA_LENGTH, -1L),
            )
        }
        return START_NOT_STICKY
    }

    private fun apply(t: String, x: String, p: Boolean, pos: Long, len: Long) {
        title = t
        text = x
        playing = p
        positionMs = pos
        lengthMs = len
        // A known length gives the notification and lock screen a seek bar.
        val meta = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, text)
        if (lengthMs > 0) meta.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, lengthMs)
        session.setMetadata(meta.build())
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY_PAUSE or PlaybackStateCompat.ACTION_STOP or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                        (if (lengthMs > 0) PlaybackStateCompat.ACTION_SEEK_TO else 0L),
                )
                .setState(
                    if (playing) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                    positionMs, 1f,
                )
                .build(),
        )
        val n = buildNotification()
        try {
            if (playing) {
                ServiceCompat.startForeground(
                    this, NOTIFICATION_ID, n,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                    } else {
                        0
                    },
                )
                foreground = true
            } else {
                // Paused: let Android reclaim us if it needs to, keep the controls.
                if (foreground) ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
                foreground = false
                getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, n)
            }
        } catch (_: Exception) {
            // Android 12+ refuses to start a foreground service from the
            // background in rare cases; playback continues regardless.
        }
    }

    private fun buildNotification() =
        NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_chipdeck)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openAppIntent())
            .setDeleteIntent(actionIntent("dismiss", 4))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setOngoing(playing)
            .addAction(android.R.drawable.ic_media_previous, "Previous", actionIntent("previous", 1))
            .addAction(
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "Pause" else "Play",
                actionIntent("toggle", 2),
            )
            .addAction(android.R.drawable.ic_media_next, "Next", actionIntent("next", 3))
            .setStyle(
                MediaStyle().setMediaSession(session.sessionToken).setShowActionsInCompactView(0, 1, 2),
            )
            .build()

    private fun actionIntent(action: String, code: Int): PendingIntent =
        PendingIntent.getService(
            this, code,
            Intent(this, PlaybackService::class.java).putExtra(EXTRA_ACTION, action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun openAppIntent(): PendingIntent =
        PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    override fun onTaskRemoved(rootIntent: Intent?) {
        // App swiped away from recents: stop playing and go away. The audio
        // runs in native code, so end the process to be sure it stops even
        // if the Flutter engine is already gone.
        onAction?.invoke("stop")
        stopSelf()
        android.os.Handler(mainLooper).postDelayed(
            { android.os.Process.killProcess(android.os.Process.myPid()) }, 300,
        )
    }

    override fun onDestroy() {
        instance = null
        unregisterReceiver(noisy)
        session.release()
        getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL = "playback"
        private const val NOTIFICATION_ID = 1
        private const val EXTRA_ACTION = "action"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_PLAYING = "playing"
        private const val EXTRA_POSITION = "positionMs"
        private const val EXTRA_LENGTH = "lengthMs"

        private var instance: PlaybackService? = null

        /** Set by MainActivity: forwards "toggle", "next", ... to Dart. */
        var onAction: ((String) -> Unit)? = null

        fun update(
            context: Context, title: String, text: String, playing: Boolean,
            positionMs: Long, lengthMs: Long,
        ) {
            val s = instance
            if (s != null) {
                s.apply(title, text, playing, positionMs, lengthMs)
                return
            }
            if (!playing) return // nothing to show until something plays
            val intent = Intent(context, PlaybackService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_PLAYING, true)
                .putExtra(EXTRA_POSITION, positionMs)
                .putExtra(EXTRA_LENGTH, lengthMs)
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (_: Exception) {
            }
        }

        fun stop(context: Context) {
            instance?.let {
                ServiceCompat.stopForeground(it, ServiceCompat.STOP_FOREGROUND_REMOVE)
                it.stopSelf()
            }
        }
    }
}
