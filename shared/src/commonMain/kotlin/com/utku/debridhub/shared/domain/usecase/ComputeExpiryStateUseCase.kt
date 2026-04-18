package com.utku.debridhub.shared.domain.usecase

import com.utku.debridhub.shared.domain.model.ExpiryState

class ComputeExpiryStateUseCase(
    private val expiringSoonThresholdDays: Int = 7
) {
    operator fun invoke(isPremium: Boolean, remainingDays: Int?): ExpiryState {
        if (!isPremium) return ExpiryState.EXPIRED
        if (remainingDays == null) return ExpiryState.UNKNOWN
        if (remainingDays <= 0) return ExpiryState.EXPIRED
        if (remainingDays <= expiringSoonThresholdDays) return ExpiryState.EXPIRING_SOON
        return ExpiryState.ACTIVE
    }
}
