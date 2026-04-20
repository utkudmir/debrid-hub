package app.debridhub.shared.platform

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import app.debridhub.shared.domain.model.ScheduledReminder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class NotificationSchedulerImpl(
    private val context: Context
) : NotificationScheduler {
    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private val prefs = context.getSharedPreferences("debridhub_notifications", Context.MODE_PRIVATE)

    override suspend fun requestPermissionIfNeeded(): Boolean = areNotificationsEnabled()

    override suspend fun areNotificationsEnabled(): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled()

    override suspend fun schedule(reminders: List<ScheduledReminder>) = withContext(Dispatchers.IO) {
        cancelAll()
        ReminderAlarmReceiver.ensureNotificationChannel(context)

        val ids = mutableSetOf<String>()
        reminders.forEach { reminder ->
            val notificationId = reminder.fireAt.epochSeconds.toInt()
            val intent = Intent(context, ReminderAlarmReceiver::class.java)
                .putExtra(ReminderAlarmReceiver.EXTRA_NOTIFICATION_ID, notificationId)
                .putExtra(ReminderAlarmReceiver.EXTRA_MESSAGE, reminder.message)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                notificationId,
                intent,
                PendingIntent.FLAG_IMMUTABLE
            )
            val triggerAtMillis = reminder.fireAt.toEpochMilliseconds()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            }
            ids += notificationId.toString()
        }

        prefs.edit().putStringSet(KEY_NOTIFICATION_IDS, ids).apply()
    }

    override suspend fun cancelAll() = withContext(Dispatchers.IO) {
        val ids = prefs.getStringSet(KEY_NOTIFICATION_IDS, emptySet()).orEmpty()
        ids.forEach { idString ->
            val notificationId = idString.toIntOrNull() ?: return@forEach
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                notificationId,
                Intent(context, ReminderAlarmReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            if (pendingIntent != null) {
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
            }
        }
        prefs.edit().remove(KEY_NOTIFICATION_IDS).apply()
    }

    private companion object {
        const val KEY_NOTIFICATION_IDS = "notification_ids"
    }
}
