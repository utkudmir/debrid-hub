package com.utku.debridhub.shared.reminders

import com.utku.debridhub.shared.domain.model.AccountStatus
import com.utku.debridhub.shared.domain.model.ExpiryState
import com.utku.debridhub.shared.domain.model.ReminderConfig
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ReminderPlannerTest {
    @Test
    fun `planner schedules reminders for configured days`() {
        val planner = ReminderPlanner()
        val now = Clock.System.now()
        val expiry = Instant.fromEpochMilliseconds(now.toEpochMilliseconds() + (10L * MILLIS_PER_DAY))
        val status = AccountStatus(
            username = "test",
            expiration = expiry,
            remainingDays = 10,
            premiumSeconds = 864000,
            isPremium = true,
            lastCheckedAt = now,
            expiryState = ExpiryState.ACTIVE
        )

        val result = planner.planReminders(
            now = now,
            accountStatus = status,
            config = ReminderConfig(enabled = true, daysBefore = setOf(7, 3, 1), notifyOnExpiry = true)
        )

        assertTrue(result.size >= 4)
        assertTrue(result.zipWithNext { a, b -> a.fireAt <= b.fireAt }.all { it })
    }

    @Test
    fun `planner returns empty when disabled`() {
        val planner = ReminderPlanner()
        val now = Clock.System.now()
        val status = AccountStatus(
            username = null,
            expiration = Instant.fromEpochMilliseconds(now.toEpochMilliseconds() + (5L * MILLIS_PER_DAY)),
            remainingDays = 5,
            premiumSeconds = 432000,
            isPremium = true,
            lastCheckedAt = now,
            expiryState = ExpiryState.EXPIRING_SOON
        )

        val result = planner.planReminders(now, status, ReminderConfig(enabled = false))
        assertTrue(result.isEmpty())
    }

    @Test
    fun `planner ignores invalid day offsets and keeps future reminders sorted`() {
        val planner = ReminderPlanner()
        val now = Clock.System.now()
        val expiry = Instant.fromEpochMilliseconds(now.toEpochMilliseconds() + (2L * MILLIS_PER_DAY))
        val status = AccountStatus(
            username = "test",
            expiration = expiry,
            remainingDays = 2,
            premiumSeconds = 172800,
            isPremium = true,
            lastCheckedAt = now,
            expiryState = ExpiryState.EXPIRING_SOON
        )

        val result = planner.planReminders(
            now = now,
            accountStatus = status,
            config = ReminderConfig(enabled = true, daysBefore = setOf(-3, 0, 1), notifyOnExpiry = true)
        )

        assertEquals(2, result.size)
        assertEquals("Your Real-Debrid subscription expires in 1 day", result.first().message)
        assertTrue(result.zipWithNext { a, b -> a.fireAt <= b.fireAt }.all { it })
    }

    @Test
    fun `planner includes post-expiry follow-up when expiry was less than a day ago`() {
        val planner = ReminderPlanner()
        val now = Clock.System.now()
        val expiry = Instant.fromEpochMilliseconds(now.toEpochMilliseconds() - (12L * 60L * 60L * 1000L))
        val status = AccountStatus(
            username = "test",
            expiration = expiry,
            remainingDays = 0,
            premiumSeconds = 0,
            isPremium = false,
            lastCheckedAt = now,
            expiryState = ExpiryState.EXPIRED
        )

        val result = planner.planReminders(
            now = now,
            accountStatus = status,
            config = ReminderConfig(enabled = true, daysBefore = setOf(7, 3, 1), notifyOnExpiry = true, notifyAfterExpiry = true)
        )

        assertEquals(1, result.size)
        assertEquals("Your Real-Debrid subscription expired yesterday", result.single().message)
    }

    private companion object {
        const val MILLIS_PER_DAY = 24L * 60L * 60L * 1000L
    }
}
