package app.debridhub.shared.data.remote

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.forms.FormDataContent
import io.ktor.client.request.get
import io.ktor.client.request.headers
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.parameters
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

interface RealDebridService {
    suspend fun getUser(accessToken: String): UserDto
    suspend fun getDeviceCode(clientId: String): DeviceCodeResponse
    suspend fun getDeviceCredentials(clientId: String, deviceCode: String): DeviceCredentialsResponse
    suspend fun exchangeToken(clientId: String, clientSecret: String, deviceCode: String): TokenResponse
    suspend fun refreshToken(clientId: String, clientSecret: String, refreshToken: String): TokenResponse
}

class RealDebridApi(
    private val httpClient: HttpClient,
    private val logger: (String) -> Unit = {}
) : RealDebridService {
    private var preferredApiHost = API_HOSTS.first()

    override suspend fun getUser(accessToken: String): UserDto {
        return withApiHostFallback("GET /rest/1.0/user") { apiHost ->
            val response = httpClient.get("$apiHost/rest/1.0/user") {
                headers {
                    append("Authorization", "Bearer $accessToken")
                }
            }
            response.body()
        }
    }

    override suspend fun getDeviceCode(clientId: String): DeviceCodeResponse {
        return withApiHostFallback("GET /oauth/v2/device/code") { apiHost ->
            val response = httpClient.get("$apiHost/oauth/v2/device/code?client_id=$clientId&new_credentials=yes")
            response.body()
        }
    }

    override suspend fun getDeviceCredentials(clientId: String, deviceCode: String): DeviceCredentialsResponse {
        return withApiHostFallback("GET /oauth/v2/device/credentials") { apiHost ->
            val response = httpClient.get("$apiHost/oauth/v2/device/credentials?client_id=$clientId&code=$deviceCode")
            response.body()
        }
    }

    override suspend fun exchangeToken(
        clientId: String,
        clientSecret: String,
        deviceCode: String
    ): TokenResponse {
        return withApiHostFallback("POST /oauth/v2/token (device)") { apiHost ->
            val response = httpClient.post("$apiHost/oauth/v2/token") {
                setBody(FormDataContent(parameters {
                    append("client_id", clientId)
                    append("client_secret", clientSecret)
                    append("code", deviceCode)
                    append("grant_type", "http://oauth.net/grant_type/device/1.0")
                }))
            }
            response.body()
        }
    }

    override suspend fun refreshToken(
        clientId: String,
        clientSecret: String,
        refreshToken: String
    ): TokenResponse {
        return withApiHostFallback("POST /oauth/v2/token (refresh)") { apiHost ->
            val response = httpClient.post("$apiHost/oauth/v2/token") {
                setBody(FormDataContent(parameters {
                    append("client_id", clientId)
                    append("client_secret", clientSecret)
                    append("code", refreshToken)
                    append("grant_type", "http://oauth.net/grant_type/device/1.0")
                }))
            }
            response.body()
        }
    }

    private suspend fun <T> withApiHostFallback(
        operation: String,
        request: suspend (apiHost: String) -> T
    ): T {
        var lastError: Throwable? = null

        for ((index, apiHost) in candidateHosts().withIndex()) {
            log("Attempting $operation via $apiHost")
            val result = runCatching { request(apiHost) }.getOrElse { error ->
                if (error is CancellationException) {
                    throw error
                }
                lastError = error
                val willRetry = index < API_HOSTS.lastIndex && shouldRetryWithAlternateHost(error)
                log(
                    buildString {
                        append("Failure on $operation via $apiHost: ")
                        append(error::class.simpleName ?: "UnknownError")
                        append(" - ")
                        append(error.message ?: "<no message>")
                        if (willRetry) {
                            append(". Retrying on alternate Real-Debrid host.")
                        }
                    }
                )
                if (!willRetry) {
                    throw error
                }
                continue
            }

            if (preferredApiHost != apiHost) {
                log("Switching preferred Real-Debrid host to $apiHost")
            }
            preferredApiHost = apiHost
            return result
        }

        val terminalError = lastError ?: error("Real-Debrid request failed before any host was attempted.")
        throw terminalError
    }

    private fun candidateHosts(): List<String> =
        listOf(preferredApiHost) + API_HOSTS.filterNot { it == preferredApiHost }

    private fun shouldRetryWithAlternateHost(error: Throwable): Boolean {
        val normalized = buildString {
            append(error::class.simpleName.orEmpty())
            append(' ')
            generateSequence(error) { it.cause }
                .mapNotNull { it.message }
                .joinTo(this, separator = " ")
        }.lowercase()

        return transportFailureSignals.any(normalized::contains)
    }

    private fun log(message: String) {
        logger("[RealDebridApi] $message")
    }

    private companion object {
        val API_HOSTS = listOf(
            "https://api.real-debrid.com",
            "https://api-1.real-debrid.com"
        )

        val transportFailureSignals = listOf(
            "secure connection",
            "ssl",
            "tls",
            "handshake",
            "wrong version number",
            "protocol version",
            "plaintext connection",
            "unrecognized ssl message",
            "network is unreachable",
            "failed to connect",
            "timed out",
            "timeout",
            "connection reset",
            "proxy",
            "middlebox"
        )
    }
}

@Serializable
data class UserDto(
    val id: Int,
    val username: String? = null,
    val email: String? = null,
    val points: Int? = null,
    val locale: String? = null,
    val avatar: String? = null,
    val type: String? = null,
    val premium: Long? = null,
    val expiration: String? = null
)

@Serializable
data class DeviceCodeResponse(
    @SerialName("device_code") val deviceCode: String,
    @SerialName("user_code") val userCode: String,
    @SerialName("verification_url") val verificationUrl: String,
    @SerialName("direct_verification_url") val directVerificationUrl: String? = null,
    @SerialName("expires_in") val expiresIn: Long,
    val interval: Long
)

@Serializable
data class DeviceCredentialsResponse(
    @SerialName("client_id") val clientId: String? = null,
    @SerialName("client_secret") val clientSecret: String? = null,
    val error: String? = null
)

@Serializable
data class TokenResponse(
    @SerialName("access_token") val accessToken: String,
    @SerialName("refresh_token") val refreshToken: String,
    @SerialName("expires_in") val expiresIn: Long
)

@Serializable
data class ApiErrorDto(
    val error: String? = null,
    @SerialName("error_code") val errorCode: Int? = null
)
