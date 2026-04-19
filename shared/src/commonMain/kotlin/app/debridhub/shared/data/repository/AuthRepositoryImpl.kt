package app.debridhub.shared.data.repository

import app.debridhub.shared.data.remote.ApiErrorDto
import app.debridhub.shared.data.remote.DeviceCredentialsResponse
import app.debridhub.shared.data.remote.RealDebridService
import app.debridhub.shared.domain.model.AuthPollResult
import app.debridhub.shared.domain.model.DeviceAuthSession
import app.debridhub.shared.domain.model.StoredAuthState
import app.debridhub.shared.domain.repository.AuthRepository
import app.debridhub.shared.platform.SecureTokenStore
import io.ktor.client.plugins.ResponseException
import io.ktor.client.statement.bodyAsText
import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.Instant
import kotlinx.datetime.plus
import kotlinx.serialization.json.Json

class AuthRepositoryImpl(
    private val api: RealDebridService,
    private val tokenStore: SecureTokenStore,
    private val clientId: String = DEFAULT_CLIENT_ID,
    private val json: Json = Json { ignoreUnknownKeys = true },
    private val nowProvider: () -> Instant = { Clock.System.now() }
) : AuthRepository {
    private var currentDeviceCode: String? = null
    private var currentSession: DeviceAuthSession? = null

    override suspend fun startAuthorization(): DeviceAuthSession {
        return try {
            val response = api.getDeviceCode(clientId)
            val session = DeviceAuthSession(
                userCode = response.userCode,
                verificationUrl = response.verificationUrl,
                directVerificationUrl = response.directVerificationUrl,
                pollIntervalSeconds = response.interval,
                expiresAt = nowProvider().plus(response.expiresIn, DateTimeUnit.SECOND)
            )
            currentDeviceCode = response.deviceCode
            currentSession = session
            session
        } catch (error: ResponseException) {
            val apiError = parseApiError(error)
            throw IllegalStateException(
                apiError?.error ?: error.message ?: "Unable to start authorization.",
                error
            )
        }
    }

    override suspend fun pollAuthorization(): AuthPollResult {
        val session = currentSession ?: return AuthPollResult.Failure(
            code = "missing_session",
            message = "Authorization has not been started."
        )
        val deviceCode = currentDeviceCode ?: return AuthPollResult.Failure(
            code = "missing_device_code",
            message = "Authorization has not been started."
        )

        if (nowProvider() >= session.expiresAt) {
            clearPendingSession()
            return AuthPollResult.Expired
        }

        return runCatching {
            val credentials = api.getDeviceCredentials(clientId, deviceCode)
            authorizeWithCredentials(credentials, deviceCode)
        }.getOrElse { error ->
            when (error) {
                is ResponseException -> {
                    val apiError = parseApiError(error)
                    mapAuthorizationError(apiError?.error)
                }

                else -> AuthPollResult.Failure(null, error.message ?: "Authorization failed.")
            }
        }
    }

    override suspend fun getStoredAuthState(): StoredAuthState? = tokenStore.read()

    override suspend fun ensureValidAccessToken(): String? {
        val state = tokenStore.read() ?: return null
        val now = nowProvider()
        if (state.accessTokenExpiresAt > now) {
            return state.accessToken
        }
        return refresh(state)
    }

    override suspend fun isAuthenticated(): Boolean = ensureValidAccessToken() != null

    override suspend fun disconnect() {
        clearPendingSession()
        tokenStore.clear()
    }

    private suspend fun authorizeWithCredentials(
        credentials: DeviceCredentialsResponse,
        deviceCode: String
    ): AuthPollResult {
        val realClientId = credentials.clientId
        val realClientSecret = credentials.clientSecret

        return if (realClientId == null || realClientSecret == null) {
            mapAuthorizationError(credentials.error)
        } else {
            val tokenResponse = api.exchangeToken(realClientId, realClientSecret, deviceCode)
            val authState = StoredAuthState(
                accessToken = tokenResponse.accessToken,
                refreshToken = tokenResponse.refreshToken,
                clientId = realClientId,
                clientSecret = realClientSecret,
                accessTokenExpiresAt = nowProvider().plus(tokenResponse.expiresIn, DateTimeUnit.SECOND)
            )
            tokenStore.write(authState)
            clearPendingSession()
            AuthPollResult.Authorized(authState)
        }
    }

    private fun mapAuthorizationError(code: String?): AuthPollResult {
        return when (code) {
            "authorization_pending", null -> AuthPollResult.Pending
            "access_denied" -> {
                clearPendingSession()
                AuthPollResult.Denied
            }

            "expired_token" -> {
                clearPendingSession()
                AuthPollResult.Expired
            }

            else -> AuthPollResult.Failure(code, code)
        }
    }

    private suspend fun refresh(state: StoredAuthState): String? {
        return runCatching {
            val refreshed = api.refreshToken(
                clientId = state.clientId,
                clientSecret = state.clientSecret,
                refreshToken = state.refreshToken
            )
            val newState = state.copy(
                accessToken = refreshed.accessToken,
                refreshToken = refreshed.refreshToken,
                accessTokenExpiresAt = nowProvider().plus(refreshed.expiresIn, DateTimeUnit.SECOND)
            )
            tokenStore.write(newState)
            newState.accessToken
        }.getOrElse {
            tokenStore.clear()
            null
        }
    }

    private suspend fun parseApiError(error: ResponseException): ApiErrorDto? {
        return runCatching {
            json.decodeFromString<ApiErrorDto>(error.response.bodyAsText())
        }.getOrNull()
    }

    private fun clearPendingSession() {
        currentDeviceCode = null
        currentSession = null
    }

    companion object {
        const val DEFAULT_CLIENT_ID: String = "X245A4XAIBGVM"
    }
}
