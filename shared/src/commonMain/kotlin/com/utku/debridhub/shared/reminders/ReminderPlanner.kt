package com.utku.debridhub.shared.reminders

import com.utku.debridhub.shared.domain.model.AccountStatus
import com.utku.debridhub.shared.domain.model.ReminderConfig
import com.utku.debridhub.shared.domain.model.ScheduledReminder
import kotlinx.datetime.Instant

class ReminderPlanner {
    fun planReminders(
        now: Instant,
        accountStatus: AccountStatus,
        config: ReminderConfig
    ): List<ScheduledReminder> {
        val expiry = accountStatus.expiration ?: return emptyList()
        if (!config.enabled) return emptyList()

        val reminders = buildList {
            for (daysBefore in config.daysBefore.filter { it > 0 }.sortedDescending()) {
                val fireAt = Instant.fromEpochMilliseconds(
                    expiry.toEpochMilliseconds() - (daysBefore * MILLIS_PER_DAY)
                )
                if (fireAt > now) {
                    add(
                        ScheduledReminder(
                            fireAt = fireAt,
                            message = "Your Real-Debrid subscription expires in ${daysBefore.dayLabel()}"
                        )
                    )
                }
            }
            if (config.notifyOnExpiry && expiry > now) {
                add(
                    ScheduledReminder(
                        fireAt = expiry,
                        message = "Your Real‑Debrid subscription expires today"
                    )
                )
            }
            if (config.notifyAfterExpiry) {
                val afterExpiry = Instant.fromEpochMilliseconds(
                    expiry.toEpochMilliseconds() + MILLIS_PER_DAY
                )
                if (afterExpiry > now) {
                    add(
                        ScheduledReminder(
                            fireAt = afterExpiry,
                            message = "Your Real-Debrid subscription expired yesterday"
                        )
                    )
                }
            }
        }

        return reminders.sortedBy { it.fireAt }
    }

    private companion object {
        const val MILLIS_PER_DAY = 24L * 60L * 60L * 1000L
    }
}

private fun Int.dayLabel(): String = if (this == 1) "1 day" else "$this days"
