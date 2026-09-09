package com.zcoderemote.zcode_remote

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.security.MessageDigest

object TaskNotificationEvents {
    var listener: ((String, String?) -> Unit)? = null
    private const val PREFS = "task_progress_runtime"
    fun dismissed(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getBoolean("dismissed", false)
    fun setDismissed(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("dismissed", value).apply()
    }
}

class DismissProgressReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        TaskNotificationEvents.setDismissed(context, true)
        context.stopService(Intent(context, TaskProgressService::class.java))
        TaskNotificationEvents.listener?.invoke("onDismiss", null)
    }
}

class TaskProgressService : Service() {
    companion object {
        const val CHANNEL = "task_progress"
        const val FINISHED_CHANNEL = "task_finished"
        const val ID = 1001
        @Volatile var instance: TaskProgressService? = null
            private set
        @Volatile private var starting = false
        val runningOrStarting: Boolean get() = instance != null || starting

        fun createChannels(context: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            val manager = context.getSystemService(NotificationManager::class.java)
            for ((id, name) in listOf(CHANNEL to "任务进度", FINISHED_CHANNEL to "任务结果")) {
                manager.createNotificationChannel(NotificationChannel(id, name, NotificationManager.IMPORTANCE_LOW).apply {
                    setSound(null, null)
                    enableVibration(false)
                })
            }
        }

        fun show(context: Context, title: String, text: String, shortText: String, payload: String, allowStart: Boolean): Boolean {
            if (TaskNotificationEvents.dismissed(context)) return false
            val running = instance
            if (running != null) {
                running.update(title, text, shortText, payload)
                return true
            }
            if (!allowStart) return false
            starting = true
            try {
                ContextCompat.startForegroundService(context, Intent(context, TaskProgressService::class.java).apply {
                    putExtra("title", title); putExtra("text", text)
                    putExtra("shortText", shortText); putExtra("payload", payload)
                })
            } catch (error: Exception) {
                starting = false
                throw error
            }
            return true
        }

        private fun tapIntent(context: Context, key: String, payload: String): PendingIntent {
            val digest = MessageDigest.getInstance("SHA-256").digest(key.toByteArray())
                .joinToString("") { "%02x".format(it) }
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                data = Uri.parse("zcoderemote://task/$digest")
                putExtra("notificationTask", payload)
            }
            return PendingIntent.getActivity(context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        fun finished(context: Context, title: String, text: String, key: String, payload: String) {
            createChannels(context)
            val notification = NotificationCompat.Builder(context, FINISHED_CHANNEL)
                .setSmallIcon(R.drawable.ic_task_progress)
                .setContentTitle(title).setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setContentIntent(tapIntent(context, key, payload))
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setAutoCancel(true).build()
            NotificationManagerCompat.from(context).notify(key, 2001, notification)
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        starting = false
        createChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null || TaskNotificationEvents.dismissed(this)) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        startForeground(ID, notification(
            intent.getStringExtra("title") ?: "任务运行中",
            intent.getStringExtra("text") ?: "",
            intent.getStringExtra("shortText") ?: "工作中",
            intent.getStringExtra("payload") ?: "{}"
        ))
        // A restarted service has no Dart task subscription; never resurrect stale progress.
        return START_NOT_STICKY
    }

    fun update(title: String, text: String, shortText: String, payload: String) {
        NotificationManagerCompat.from(this).notify(ID, notification(title, text, shortText, payload))
    }

    private fun notification(title: String, text: String, shortText: String, payload: String): Notification {
        val dismiss = PendingIntent.getBroadcast(this, 0, Intent(this, DismissProgressReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_task_progress)
            .setContentTitle(title).setContentText(text)
            .setStyle(NotificationCompat.ProgressStyle().setProgressIndeterminate(true))
            .setShortCriticalText(shortText.take(7))
            .setRequestPromotedOngoing(true)
            .setOngoing(true).setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setContentIntent(tapIntent(this, "ongoing", payload))
            .setDeleteIntent(dismiss)
            .addAction(0, "停止显示", dismiss)
            .build()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        TaskNotificationEvents.setDismissed(this, true)
        TaskNotificationEvents.listener?.invoke("onDismiss", null)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        starting = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
