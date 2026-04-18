package com.utku.debridhub.shared.domain.model

data class ReminderConfigSnapshot(
    val enabled: Boolean = true,
    val sevenDayReminder: Boolean = true,
    val threeDayReminder: Boolean = true,
    val oneDayReminder: Boolean = true,
    val notifyOnExpiry: Boolean = true,
    val notifyAfterExpiry: Boolean = false,
)

fun ReminderConfig.toSnapshot(): ReminderConfigSnapshot = ReminderConfigSnapshot(
    enabled = enabled,
    sevenDayReminder = 7 in daysBefore,
    threeDayReminder = 3 in daysBefore,
    oneDayReminder = 1 in daysBefore,
    notifyOnExpiry = notifyOnExpiry,
    notifyAfterExpiry = notifyAfterExpiry,
)

fun ReminderConfigSnapshot.toReminderConfig(): ReminderConfig {
    val daysBefore = buildSet {
        if (sevenDayReminder) add(7)
        if (threeDayReminder) add(3)
        if (oneDayReminder) add(1)
    }

    return ReminderConfig(
        enabled = enabled,
        daysBefore = daysBefore,
        notifyOnExpiry = notifyOnExpiry,
        notifyAfterExpiry = notifyAfterExpiry,
    )
}
