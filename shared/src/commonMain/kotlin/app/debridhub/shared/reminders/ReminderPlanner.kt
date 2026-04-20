package app.debridhub.shared.reminders

import app.debridhub.shared.domain.model.AccountStatus
import app.debridhub.shared.domain.model.ReminderConfig
import app.debridhub.shared.domain.model.ScheduledReminder
import app.debridhub.shared.localization.AppLocalization
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
                            message = AppLocalization.plural(
                                key = "reminders.notification.expires_in",
                                count = daysBefore,
                                daysBefore.toString()
                            )
                        )
                    )
                }
            }
            if (config.notifyOnExpiry && expiry > now) {
                add(
                    ScheduledReminder(
                        fireAt = expiry,
                        message = AppLocalization.text("reminders.notification.expires_today")
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
                            message = AppLocalization.text("reminders.notification.expired_yesterday")
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
