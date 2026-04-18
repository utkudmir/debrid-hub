package app.debridhub.shared.data.repository

import app.debridhub.shared.domain.model.AccountStatus
import app.debridhub.shared.domain.model.ExpiryState
import app.debridhub.shared.domain.model.ReminderConfig
import app.debridhub.shared.domain.model.ScheduledReminder
import app.debridhub.shared.platform.NotificationScheduler
import app.debridhub.shared.platform.ReminderConfigStore
import app.debridhub.shared.reminders.ReminderPlanner
import kotlinx.coroutines.runBlocking
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ReminderRepositoryImplTest {
    @Test
    fun `update config persists new value`() = runBlocking {
        val configStore = FakeReminderConfigStore(ReminderConfig(enabled = false))
        val repository = ReminderRepositoryImpl(
            configStore = configStore,
            planner = ReminderPlanner(),
            notificationScheduler = FakeNotificationScheduler()
        )
        val updated = ReminderConfig(enabled = true, daysBefore = setOf(7, 1), notifyAfterExpiry = true)

        repository.updateConfig(updated)

        assertEquals(updated, configStore.storedConfig)
    }

    @Test
    fun `schedule reminders plans notifications and delegates scheduling`() = runBlocking {
        val scheduler = FakeNotificationScheduler()
        val repository = ReminderRepositoryImpl(
            configStore = FakeReminderConfigStore(ReminderConfig(enabled = true, daysBefore = setOf(7, 3), notifyOnExpiry = true)),
            planner = ReminderPlanner(),
            notificationScheduler = scheduler
        )
        val reminders = repository.scheduleReminders(sampleAccountStatus())

        assertTrue(reminders.isNotEmpty())
        assertEquals(reminders, scheduler.scheduledReminders)
    }

    @Test
    fun `cancel reminders clears scheduled notifications`() = runBlocking {
        val scheduler = FakeNotificationScheduler()
        val repository = ReminderRepositoryImpl(
            configStore = FakeReminderConfigStore(ReminderConfig()),
            planner = ReminderPlanner(),
            notificationScheduler = scheduler
        )

        repository.cancelReminders()

        assertEquals(1, scheduler.cancelCalls)
    }

    private fun sampleAccountStatus(): AccountStatus {
        val now = Clock.System.now()
        return AccountStatus(
            username = "sample-user",
            expiration = Instant.fromEpochMilliseconds(now.toEpochMilliseconds() + (10L * 24L * 60L * 60L * 1000L)),
            remainingDays = 10,
            premiumSeconds = 864000,
            isPremium = true,
            lastCheckedAt = now,
            expiryState = ExpiryState.ACTIVE
        )
    }
}

private class FakeReminderConfigStore(
    initialConfig: ReminderConfig
) : ReminderConfigStore {
    var storedConfig: ReminderConfig = initialConfig

    override suspend fun read(): ReminderConfig = storedConfig

    override suspend fun write(config: ReminderConfig) {
        storedConfig = config
    }
}

private class FakeNotificationScheduler : NotificationScheduler {
    var scheduledReminders: List<ScheduledReminder> = emptyList()
    var cancelCalls: Int = 0

    override suspend fun requestPermissionIfNeeded(): Boolean = true

    override suspend fun areNotificationsEnabled(): Boolean = true

    override suspend fun schedule(reminders: List<ScheduledReminder>) {
        scheduledReminders = reminders
    }

    override suspend fun cancelAll() {
        cancelCalls += 1
    }
}
