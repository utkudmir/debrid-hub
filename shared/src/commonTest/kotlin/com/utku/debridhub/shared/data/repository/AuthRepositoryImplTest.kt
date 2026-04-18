package com.utku.debridhub.shared.data.repository

import com.utku.debridhub.shared.data.remote.DeviceCodeResponse
import com.utku.debridhub.shared.data.remote.DeviceCredentialsResponse
import com.utku.debridhub.shared.data.remote.RealDebridService
import com.utku.debridhub.shared.data.remote.TokenResponse
import com.utku.debridhub.shared.data.remote.UserDto
import com.utku.debridhub.shared.domain.model.AuthPollResult
import com.utku.debridhub.shared.domain.model.StoredAuthState
import com.utku.debridhub.shared.platform.SecureTokenStore
import kotlinx.coroutines.runBlocking
import kotlinx.datetime.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AuthRepositoryImplTest {
    private val fixedNow = Instant.parse("2026-04-12T00:00:00Z")

    @Test
    fun `poll authorization writes tokens after device approval`() = runBlocking {
        val api = FakeRealDebridService().apply {
            deviceCodeResponse = DeviceCodeResponse(
                deviceCode = "device-code",
                userCode = "USER-CODE",
                verificationUrl = "https://real-debrid.com/device",
                directVerificationUrl = "https://real-debrid.com/device/confirm",
                expiresIn = 600,
                interval = 5
            )
            credentialsResponse = DeviceCredentialsResponse(
                clientId = "real-client-id",
                clientSecret = "real-client-secret"
            )
            tokenResponse = TokenResponse(
                accessToken = "access-token",
                refreshToken = "refresh-token",
                expiresIn = 3600
            )
        }
        val tokenStore = FakeSecureTokenStore()
        val repository = AuthRepositoryImpl(
            api = api,
            tokenStore = tokenStore,
            nowProvider = { fixedNow }
        )

        val session = repository.startAuthorization()
        val result = repository.pollAuthorization()

        assertEquals("https://real-debrid.com/device/confirm", session.directVerificationUrl)
        val authorized = assertIs<AuthPollResult.Authorized>(result)
        assertEquals("access-token", authorized.authState.accessToken)
        assertEquals("refresh-token", tokenStore.state?.refreshToken)
        assertEquals("device-code", api.exchangedDeviceCode)
    }

    @Test
    fun `ensure valid access token refreshes expired credentials and updates storage`() = runBlocking {
        val api = FakeRealDebridService().apply {
            refreshTokenResponse = TokenResponse(
                accessToken = "fresh-access-token",
                refreshToken = "fresh-refresh-token",
                expiresIn = 7200
            )
        }
        val tokenStore = FakeSecureTokenStore().apply {
            state = StoredAuthState(
                accessToken = "stale-access-token",
                refreshToken = "stale-refresh-token",
                clientId = "client-id",
                clientSecret = "client-secret",
                accessTokenExpiresAt = Instant.parse("2026-04-11T23:00:00Z")
            )
        }
        val repository = AuthRepositoryImpl(
            api = api,
            tokenStore = tokenStore,
            nowProvider = { fixedNow }
        )

        val token = repository.ensureValidAccessToken()

        assertEquals("fresh-access-token", token)
        assertEquals("stale-refresh-token", api.refreshedTokenCode)
        assertEquals("fresh-refresh-token", tokenStore.state?.refreshToken)
        assertEquals(
            Instant.parse("2026-04-12T02:00:00Z"),
            tokenStore.state?.accessTokenExpiresAt
        )
    }

    @Test
    fun `failed token refresh clears persisted auth state`() = runBlocking {
        val api = FakeRealDebridService().apply {
            refreshFailure = IllegalStateException("refresh failed")
        }
        val tokenStore = FakeSecureTokenStore().apply {
            state = StoredAuthState(
                accessToken = "stale-access-token",
                refreshToken = "stale-refresh-token",
                clientId = "client-id",
                clientSecret = "client-secret",
                accessTokenExpiresAt = Instant.parse("2026-04-11T23:00:00Z")
            )
        }
        val repository = AuthRepositoryImpl(
            api = api,
            tokenStore = tokenStore,
            nowProvider = { fixedNow }
        )

        val token = repository.ensureValidAccessToken()

        assertNull(token)
        assertNull(tokenStore.state)
        assertTrue(tokenStore.clearCalls > 0)
    }
}

private class FakeSecureTokenStore : SecureTokenStore {
    var state: StoredAuthState? = null
    var clearCalls: Int = 0

    override suspend fun read(): StoredAuthState? = state

    override suspend fun write(state: StoredAuthState) {
        this.state = state
    }

    override suspend fun clear() {
        clearCalls += 1
        state = null
    }
}

private class FakeRealDebridService : RealDebridService {
    var deviceCodeResponse: DeviceCodeResponse? = null
    var credentialsResponse: DeviceCredentialsResponse? = null
    var tokenResponse: TokenResponse? = null
    var refreshTokenResponse: TokenResponse? = null
    var refreshFailure: Throwable? = null
    var exchangedDeviceCode: String? = null
    var refreshedTokenCode: String? = null

    override suspend fun getUser(accessToken: String): UserDto {
        error("Not needed for this test")
    }

    override suspend fun getDeviceCode(clientId: String): DeviceCodeResponse =
        requireNotNull(deviceCodeResponse)

    override suspend fun getDeviceCredentials(clientId: String, deviceCode: String): DeviceCredentialsResponse =
        requireNotNull(credentialsResponse)

    override suspend fun exchangeToken(clientId: String, clientSecret: String, deviceCode: String): TokenResponse {
        exchangedDeviceCode = deviceCode
        return requireNotNull(tokenResponse)
    }

    override suspend fun refreshToken(clientId: String, clientSecret: String, refreshToken: String): TokenResponse {
        refreshedTokenCode = refreshToken
        refreshFailure?.let { throw it }
        return requireNotNull(refreshTokenResponse)
    }
}
