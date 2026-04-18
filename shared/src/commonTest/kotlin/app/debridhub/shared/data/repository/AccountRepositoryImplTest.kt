package app.debridhub.shared.data.repository

import app.debridhub.shared.data.remote.DeviceCodeResponse
import app.debridhub.shared.data.remote.DeviceCredentialsResponse
import app.debridhub.shared.data.remote.RealDebridService
import app.debridhub.shared.data.remote.TokenResponse
import app.debridhub.shared.data.remote.UserDto
import app.debridhub.shared.domain.model.AccountStatus
import app.debridhub.shared.domain.model.StoredAuthState
import app.debridhub.shared.domain.repository.AuthRepository
import kotlinx.coroutines.runBlocking
import kotlinx.datetime.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AccountRepositoryImplTest {
    private val now = Instant.parse("2026-04-18T09:00:00Z")

    @Test
    fun `refresh account status maps api fields into domain model and cache`() = runBlocking {
        val api = FakeAccountRealDebridService().apply {
            userDto = UserDto(
                id = 7,
                username = "sample-user",
                type = "premium",
                premium = 432000,
                expiration = "2026-04-23T09:00:00Z"
            )
        }
        val repository = AccountRepositoryImpl(
            api = api,
            authRepository = FakeAuthRepository(accessToken = "access-token"),
            nowProvider = { now }
        )

        val result = repository.refreshAccountStatus()

        val status = result.getOrThrow()
        assertEquals("sample-user", status.username)
        assertEquals(5, status.remainingDays)
        assertTrue(status.isPremium)
        assertEquals(now, status.lastCheckedAt)
        assertEquals(status, repository.getCachedAccountStatus())
        assertEquals("access-token", api.lastAccessToken)
    }

    @Test
    fun `refresh account status fails early when not authenticated`() = runBlocking {
        val api = FakeAccountRealDebridService()
        val repository = AccountRepositoryImpl(
            api = api,
            authRepository = FakeAuthRepository(accessToken = null),
            nowProvider = { now }
        )

        val result = repository.refreshAccountStatus()

        assertTrue(result.isFailure)
        assertNull(repository.getCachedAccountStatus())
        assertNull(api.lastAccessToken)
    }
}

private class FakeAuthRepository(
    private val accessToken: String?
) : AuthRepository {
    override suspend fun startAuthorization() = error("Unused")

    override suspend fun pollAuthorization() = error("Unused")

    override suspend fun getStoredAuthState(): StoredAuthState? = null

    override suspend fun ensureValidAccessToken(): String? = accessToken

    override suspend fun isAuthenticated(): Boolean = accessToken != null

    override suspend fun disconnect() = Unit
}

private class FakeAccountRealDebridService : RealDebridService {
    var userDto: UserDto? = null
    var lastAccessToken: String? = null

    override suspend fun getUser(accessToken: String): UserDto {
        lastAccessToken = accessToken
        return requireNotNull(userDto)
    }

    override suspend fun getDeviceCode(clientId: String): DeviceCodeResponse = error("Unused")

    override suspend fun getDeviceCredentials(clientId: String, deviceCode: String): DeviceCredentialsResponse = error("Unused")

    override suspend fun exchangeToken(clientId: String, clientSecret: String, deviceCode: String): TokenResponse = error("Unused")

    override suspend fun refreshToken(clientId: String, clientSecret: String, refreshToken: String): TokenResponse = error("Unused")
}
