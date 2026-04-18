package com.utku.debridhub.shared.platform

import com.utku.debridhub.shared.domain.model.ScheduledReminder
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.datetime.Clock
import platform.UserNotifications.UNAuthorizationOptionAlert
import platform.UserNotifications.UNAuthorizationOptionBadge
import platform.UserNotifications.UNAuthorizationOptionSound
import platform.UserNotifications.UNAuthorizationStatusAuthorized
import platform.UserNotifications.UNAuthorizationStatusEphemeral
import platform.UserNotifications.UNAuthorizationStatusProvisional
import platform.UserNotifications.UNMutableNotificationContent
import platform.UserNotifications.UNNotificationRequest
import platform.UserNotifications.UNNotificationSettings
import platform.UserNotifications.UNTimeIntervalNotificationTrigger
import platform.UserNotifications.UNUserNotificationCenter
import kotlin.coroutines.resume

class NotificationSchedulerImpl(
    private val notificationCenter: UNUserNotificationCenter = UNUserNotificationCenter.currentNotificationCenter()
) : NotificationScheduler {
    override suspend fun requestPermissionIfNeeded(): Boolean = suspendCancellableCoroutine { continuation ->
        notificationCenter.requestAuthorizationWithOptions(
            options = UNAuthorizationOptionAlert or UNAuthorizationOptionSound or UNAuthorizationOptionBadge
        ) { granted, _ ->
            continuation.resume(granted)
        }
    }

    override suspend fun areNotificationsEnabled(): Boolean = suspendCancellableCoroutine { continuation ->
        notificationCenter.getNotificationSettingsWithCompletionHandler { settings: UNNotificationSettings? ->
            val enabled = when (settings?.authorizationStatus) {
                UNAuthorizationStatusAuthorized,
                UNAuthorizationStatusProvisional,
                UNAuthorizationStatusEphemeral -> true
                else -> false
            }
            continuation.resume(enabled)
        }
    }

    override suspend fun schedule(reminders: List<ScheduledReminder>) {
        cancelAll()
        reminders.forEach { reminder ->
            val timeInterval = ((reminder.fireAt.toEpochMilliseconds() - Clock.System.now().toEpochMilliseconds()) / 1000.0)
                .coerceAtLeast(1.0)
            val content = UNMutableNotificationContent().apply {
                setTitle("DebridHub")
                setBody(reminder.message)
            }
            val trigger = UNTimeIntervalNotificationTrigger.triggerWithTimeInterval(timeInterval, repeats = false)
            val request = UNNotificationRequest.requestWithIdentifier(
                identifier = "debridhub.${reminder.fireAt.toEpochMilliseconds()}",
                content = content,
                trigger = trigger
            )
            notificationCenter.addNotificationRequest(request, withCompletionHandler = null)
        }
    }

    override suspend fun cancelAll() {
        notificationCenter.removeAllPendingNotificationRequests()
    }
}
