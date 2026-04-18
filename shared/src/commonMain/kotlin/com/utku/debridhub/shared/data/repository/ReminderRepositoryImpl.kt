package com.utku.debridhub.shared.data.repository

import com.utku.debridhub.shared.domain.model.AccountStatus
import com.utku.debridhub.shared.domain.model.ReminderConfig
import com.utku.debridhub.shared.domain.model.ScheduledReminder
import com.utku.debridhub.shared.domain.repository.ReminderRepository
import com.utku.debridhub.shared.platform.NotificationScheduler
import com.utku.debridhub.shared.platform.ReminderConfigStore
import com.utku.debridhub.shared.reminders.ReminderPlanner
import kotlinx.datetime.Clock

class ReminderRepositoryImpl(
    private val configStore: ReminderConfigStore,
    private val planner: ReminderPlanner,
    private val notificationScheduler: NotificationScheduler
) : ReminderRepository {
    override suspend fun getConfig(): ReminderConfig = configStore.read()

    override suspend fun updateConfig(config: ReminderConfig) {
        configStore.write(config)
    }

    override suspend fun previewReminders(accountStatus: AccountStatus): List<ScheduledReminder> =
        planner.planReminders(
            now = Clock.System.now(),
            accountStatus = accountStatus,
            config = configStore.read()
        )

    override suspend fun scheduleReminders(accountStatus: AccountStatus): List<ScheduledReminder> {
        val planned = previewReminders(accountStatus)
        notificationScheduler.schedule(planned)
        return planned
    }

    override suspend fun cancelReminders() {
        notificationScheduler.cancelAll()
    }
}
