package app.debridhub.shared.domain.model

/**
 * Configuration for reminder scheduling.
 *
 * @param enabled whether reminders are globally enabled. When disabled, no
 *   notifications will be scheduled.
 * @param daysBefore set of unique days before the expiration date at which
 *   reminders should be sent. For example, a value of 7 means a notification
 *   will be scheduled 7 days before the subscription expiry.
 * @param notifyOnExpiry whether to notify on the exact day the subscription
 *   expires.
 * @param notifyAfterExpiry whether to send a follow‑up reminder one day after
 *   the subscription has expired. This can be useful to alert users that
 *   Real‑Debrid has stopped working in their other apps.
 */
data class ReminderConfig(
    val enabled: Boolean = true,
    val daysBefore: Set<Int> = setOf(7, 3, 1),
    val notifyOnExpiry: Boolean = true,
    val notifyAfterExpiry: Boolean = false,
)
