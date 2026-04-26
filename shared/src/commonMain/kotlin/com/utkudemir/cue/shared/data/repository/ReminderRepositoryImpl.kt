package com.utkudemir.cue.shared.data.repository

import com.utkudemir.cue.shared.domain.model.AccountStatus
import com.utkudemir.cue.shared.domain.model.ReminderConfig
import com.utkudemir.cue.shared.domain.model.ScheduledReminder
import com.utkudemir.cue.shared.domain.repository.ReminderRepository
import com.utkudemir.cue.shared.platform.NotificationScheduler
import com.utkudemir.cue.shared.platform.ReminderConfigStore
import com.utkudemir.cue.shared.reminders.ReminderPlanner
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

class ReminderRepositoryImpl(
    private val configStore: ReminderConfigStore,
    private val planner: ReminderPlanner,
    private val notificationScheduler: NotificationScheduler,
    private val nowProvider: () -> Instant = { Clock.System.now() }
) : ReminderRepository {
    override suspend fun getConfig(): ReminderConfig = configStore.read()

    override suspend fun updateConfig(config: ReminderConfig) {
        configStore.write(config)
    }

    override suspend fun previewReminders(accountStatus: AccountStatus): List<ScheduledReminder> =
        planner.planReminders(
            now = nowProvider(),
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
