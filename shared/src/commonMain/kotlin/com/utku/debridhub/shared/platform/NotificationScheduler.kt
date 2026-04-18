package com.utku.debridhub.shared.platform

import com.utku.debridhub.shared.domain.model.ScheduledReminder

interface NotificationScheduler {
    suspend fun requestPermissionIfNeeded(): Boolean
    suspend fun areNotificationsEnabled(): Boolean
    suspend fun schedule(reminders: List<ScheduledReminder>)
    suspend fun cancelAll()
}
