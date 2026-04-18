package app.debridhub.shared.domain.usecase

import app.debridhub.shared.domain.model.ExpiryState
import kotlin.test.Test
import kotlin.test.assertEquals

class ComputeExpiryStateUseCaseTest {
    private val useCase = ComputeExpiryStateUseCase(expiringSoonThresholdDays = 7)

    @Test
    fun `premium account with enough time left is active`() {
        assertEquals(ExpiryState.ACTIVE, useCase(isPremium = true, remainingDays = 12))
    }

    @Test
    fun `premium account near expiry is expiring soon`() {
        assertEquals(ExpiryState.EXPIRING_SOON, useCase(isPremium = true, remainingDays = 3))
    }

    @Test
    fun `non premium account is expired`() {
        assertEquals(ExpiryState.EXPIRED, useCase(isPremium = false, remainingDays = 30))
    }

    @Test
    fun `missing remaining days is unknown`() {
        assertEquals(ExpiryState.UNKNOWN, useCase(isPremium = true, remainingDays = null))
    }
}
