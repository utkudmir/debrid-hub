package com.utku.debridhub.shared.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

@Serializable
data class AccountStatus(
    val username: String?,
    val expiration: Instant?,
    val remainingDays: Int?,
    val premiumSeconds: Long?,
    val isPremium: Boolean,
    val lastCheckedAt: Instant,
    val expiryState: ExpiryState
)

@Serializable
enum class ExpiryState {
    ACTIVE,
    EXPIRING_SOON,
    EXPIRED,
    UNKNOWN
}
