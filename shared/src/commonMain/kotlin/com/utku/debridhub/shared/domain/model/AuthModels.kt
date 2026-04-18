package com.utku.debridhub.shared.domain.model

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

@Serializable
data class StoredAuthState(
    val accessToken: String,
    val refreshToken: String,
    val clientId: String,
    val clientSecret: String,
    val accessTokenExpiresAt: Instant
)

@Serializable
data class DeviceAuthSession(
    val userCode: String,
    val verificationUrl: String,
    val directVerificationUrl: String? = null,
    val pollIntervalSeconds: Long,
    val expiresAt: Instant
)

sealed interface AuthPollResult {
    data object Pending : AuthPollResult
    data class Authorized(val authState: StoredAuthState) : AuthPollResult
    data object Expired : AuthPollResult
    data object Denied : AuthPollResult
    data class Failure(val code: String?, val message: String) : AuthPollResult
}
