package com.utkudemir.cue.android

import com.utkudemir.cue.shared.CueController
import com.utkudemir.cue.shared.data.remote.ApiErrorDto
import com.utkudemir.cue.shared.data.remote.DeviceCodeResponse
import com.utkudemir.cue.shared.data.remote.DeviceCredentialsResponse
import com.utkudemir.cue.shared.data.remote.RealDebridApi
import com.utkudemir.cue.shared.data.remote.RealDebridService
import com.utkudemir.cue.shared.data.remote.TokenResponse
import com.utkudemir.cue.shared.data.remote.UserDto
import com.utkudemir.cue.shared.data.repository.AccountRepositoryImpl
import com.utkudemir.cue.shared.data.repository.AuthRepositoryImpl
import com.utkudemir.cue.shared.data.repository.DiagnosticsRepositoryImpl
import com.utkudemir.cue.shared.data.repository.ReminderRepositoryImpl
import com.utkudemir.cue.shared.domain.model.AccountStatus
import com.utkudemir.cue.shared.domain.model.AuthPollResult
import com.utkudemir.cue.shared.domain.model.DiagnosticsBundle
import com.utkudemir.cue.shared.domain.model.ExpiryState
import com.utkudemir.cue.shared.domain.model.ReminderConfig
import com.utkudemir.cue.shared.domain.model.ScheduledReminder
import com.utkudemir.cue.shared.domain.model.StoredAuthState
import com.utkudemir.cue.shared.domain.repository.AccountRepository
import com.utkudemir.cue.shared.domain.repository.AuthRepository
import com.utkudemir.cue.shared.domain.repository.DiagnosticsRepository
import com.utkudemir.cue.shared.domain.repository.ReminderRepository
import com.utkudemir.cue.shared.domain.usecase.ComputeExpiryStateUseCase
import com.utkudemir.cue.shared.domain.usecase.ExportDiagnosticsUseCase
import com.utkudemir.cue.shared.domain.usecase.GetAccountStatusUseCase
import com.utkudemir.cue.shared.domain.usecase.PreviewDiagnosticsUseCase
import com.utkudemir.cue.shared.domain.usecase.ScheduleRemindersUseCase
import com.utkudemir.cue.shared.platform.ExportedFile
import com.utkudemir.cue.shared.platform.FileExporter
import com.utkudemir.cue.shared.platform.NotificationScheduler
import com.utkudemir.cue.shared.platform.ReminderConfigStore
import com.utkudemir.cue.shared.platform.SecureTokenStore
import com.utkudemir.cue.shared.reminders.ReminderPlanner
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.runBlocking
import kotlinx.datetime.Instant
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.test.assertFailsWith

class SharedLogicCoverageTest {
    private val fixedNow = Instant.parse("2026-04-18T09:00:00Z")

    @Test
    fun `compute expiry state buckets premium lifecycle correctly`() {
        val useCase = ComputeExpiryStateUseCase(expiringSoonThresholdDays = 7)

        assertEquals(ExpiryState.ACTIVE, useCase(isPremium = true, remainingDays = 12))
        assertEquals(ExpiryState.EXPIRING_SOON, useCase(isPremium = true, remainingDays = 2))
        assertEquals(ExpiryState.UNKNOWN, useCase(isPremium = true, remainingDays = null))
        assertEquals(ExpiryState.EXPIRED, useCase(isPremium = false, remainingDays = 2))
    }

    @Test
    fun `account repository maps api response and get account status use case returns it`() = runBlocking {
        val api = FakeSharedRealDebridService().apply {
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
            authRepository = FakeSharedAuthRepository(accessToken = "access-token"),
            nowProvider = { fixedNow }
        )

        val status = GetAccountStatusUseCase(repository)().getOrThrow()

        assertEquals("sample-user", status.username)
        assertEquals(5, status.remainingDays)
        assertEquals(status, repository.getCachedAccountStatus())
    }

    @Test
    fun `get account status use case forwards refresh failures`() = runBlocking {
        val result = GetAccountStatusUseCase(
            FakeSharedAccountRepository(
                cachedStatus = null,
                refreshResult = Result.failure(IllegalStateException("not authenticated"))
            )
        )()

        assertTrue(result.isFailure)
    }

    @Test
    fun `auth repository stores approved tokens and clears broken refresh state`() = runBlocking {
        val api = FakeSharedRealDebridService().apply {
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
        val tokenStore = FakeSharedSecureTokenStore()
        val repository = AuthRepositoryImpl(api = api, tokenStore = tokenStore, nowProvider = { fixedNow })

        repository.startAuthorization()
        val result = repository.pollAuthorization()

        assertTrue(result is AuthPollResult.Authorized)
        assertEquals("refresh-token", tokenStore.state?.refreshToken)

        api.refreshFailure = IllegalStateException("refresh failed")
        tokenStore.state = tokenStore.state?.copy(accessTokenExpiresAt = Instant.parse("2026-04-18T08:00:00Z"))

        assertNull(repository.ensureValidAccessToken())
        assertTrue(tokenStore.clearCalls > 0)
    }

    @Test
    fun `auth repository returns pending denied and expired terminal states`() = runBlocking {
        val api = FakeSharedRealDebridService().apply {
            deviceCodeResponse = DeviceCodeResponse(
                deviceCode = "device-code",
                userCode = "USER-CODE",
                verificationUrl = "https://real-debrid.com/device",
                directVerificationUrl = null,
                expiresIn = 600,
                interval = 5
            )
        }
        val repository = AuthRepositoryImpl(api = api, tokenStore = FakeSharedSecureTokenStore(), nowProvider = { fixedNow })

        repository.startAuthorization()
        api.credentialsResponse = DeviceCredentialsResponse(error = "authorization_pending")
        assertEquals(AuthPollResult.Pending, repository.pollAuthorization())

        api.credentialsResponse = DeviceCredentialsResponse(error = "access_denied")
        assertEquals(AuthPollResult.Denied, repository.pollAuthorization())

        repository.startAuthorization()
        api.credentialsResponse = DeviceCredentialsResponse(error = "expired_token")
        assertEquals(AuthPollResult.Expired, repository.pollAuthorization())
    }

    @Test
    fun `auth repository reports missing session unknown failure and time expiry`() = runBlocking {
        val api = FakeSharedRealDebridService().apply {
            deviceCodeResponse = DeviceCodeResponse(
                deviceCode = "device-code",
                userCode = "USER-CODE",
                verificationUrl = "https://real-debrid.com/device",
                directVerificationUrl = null,
                expiresIn = 1,
                interval = 5
            )
        }
        var now = fixedNow
        val repository = AuthRepositoryImpl(api = api, tokenStore = FakeSharedSecureTokenStore(), nowProvider = { now })

        val missingSession = repository.pollAuthorization() as AuthPollResult.Failure
        assertEquals("missing_session", missingSession.code)

        repository.startAuthorization()
        api.credentialsResponse = DeviceCredentialsResponse(error = "server_error")
        val unknownFailure = repository.pollAuthorization() as AuthPollResult.Failure
        assertEquals("server_error", unknownFailure.code)

        repository.startAuthorization()
        now = Instant.parse("2026-04-18T09:00:02Z")
        assertEquals(AuthPollResult.Expired, repository.pollAuthorization())
    }

    @Test
    fun `account repository treats remaining premium seconds as premium and handles missing expiry`() = runBlocking {
        val api = FakeSharedRealDebridService().apply {
            userDto = UserDto(
                id = 8,
                username = "fallback-premium",
                type = "free",
                premium = 86400,
                expiration = null
            )
        }
        val repository = AccountRepositoryImpl(
            api = api,
            authRepository = FakeSharedAuthRepository(accessToken = "access-token"),
            nowProvider = { fixedNow }
        )

        val status = repository.refreshAccountStatus().getOrThrow()

        assertTrue(status.isPremium)
        assertNull(status.expiration)
        assertEquals(1, status.remainingDays)
    }

    @Test
    fun `reminder repository and schedule use case plan future reminders`() = runBlocking {
        val scheduler = FakeSharedNotificationScheduler(enabled = true)
        val reminderRepository = ReminderRepositoryImpl(
            configStore = FakeSharedReminderConfigStore(ReminderConfig(enabled = true, daysBefore = setOf(7, 3), notifyOnExpiry = true)),
            planner = ReminderPlanner(),
            notificationScheduler = scheduler,
            nowProvider = { fixedNow }
        )
        val accountStatus = sampleAccountStatus()

        val scheduled = reminderRepository.scheduleReminders(accountStatus)
        val useCaseResult = ScheduleRemindersUseCase(
            accountRepository = FakeSharedAccountRepository(refreshResult = Result.success(accountStatus), cachedStatus = accountStatus),
            reminderRepository = reminderRepository
        )().getOrThrow()

        assertFalse(scheduled.isEmpty())
        assertEquals(scheduled, scheduler.scheduledReminders)
        assertEquals(useCaseResult, scheduler.scheduledReminders)
    }

    @Test
    fun `reminder planner returns empty for disabled config and missing expiry`() {
        val planner = ReminderPlanner()

        val disabled = planner.planReminders(
            now = fixedNow,
            accountStatus = sampleAccountStatus(),
            config = ReminderConfig(enabled = false)
        )
        val missingExpiry = planner.planReminders(
            now = fixedNow,
            accountStatus = sampleAccountStatus().copy(expiration = null),
            config = ReminderConfig(enabled = true)
        )

        assertTrue(disabled.isEmpty())
        assertTrue(missingExpiry.isEmpty())
    }

    @Test
    fun `schedule reminders use case returns failure when account refresh fails`() = runBlocking {
        val reminderRepository = FakeSharedReminderRepository()

        val result = ScheduleRemindersUseCase(
            accountRepository = FakeSharedAccountRepository(
                cachedStatus = null,
                refreshResult = Result.failure(IllegalStateException("refresh failed"))
            ),
            reminderRepository = reminderRepository
        )()

        assertTrue(result.isFailure)
        assertEquals(0, reminderRepository.scheduleCalls)
    }

    @Test
    fun `schedule reminders use case returns failure when scheduling throws`() = runBlocking {
        val reminderRepository = FakeSharedReminderRepository(scheduleFailure = IllegalStateException("schedule failed"))

        val result = ScheduleRemindersUseCase(
            accountRepository = FakeSharedAccountRepository(cachedStatus = sampleAccountStatus(), refreshResult = Result.success(sampleAccountStatus())),
            reminderRepository = reminderRepository
        )()

        assertTrue(result.isFailure)
        assertEquals(1, reminderRepository.scheduleCalls)
    }

    @Test
    fun `diagnostics repository strips sensitive values and preview export use cases succeed`() = runBlocking {
        val repository = DiagnosticsRepositoryImpl(
            appVersionProvider = { "1.0.0" },
            osProvider = { "Android 16" },
            accountRepository = FakeSharedAccountRepository(cachedStatus = sampleAccountStatus()),
            additionalInfoProvider = {
                mapOf(
                    "notificationsEnabled" to "true",
                    "refreshToken" to "secret",
                    "supportEmail" to "user@example.com"
                )
            }
        )

        val preview = PreviewDiagnosticsUseCase(repository)().getOrThrow()
        val export = ExportDiagnosticsUseCase(repository, FakeSharedFileExporter())().getOrThrow()

        assertTrue(preview.contains("notificationsEnabled"))
        assertFalse(preview.contains("secret"))
        assertEquals("diagnostics.json", export.displayName)
    }

    @Test
    fun `controller syncReminders and previewReminders use account state correctly`() = runBlocking {
        val reminderRepository = FakeSharedReminderRepository(
            previewReminders = listOf(ScheduledReminder(Instant.parse("2026-04-20T09:00:00Z"), "Preview")),
            scheduledReminders = listOf(ScheduledReminder(Instant.parse("2026-04-20T09:00:00Z"), "Scheduled"))
        )
        val controller = CueController(
            authRepository = FakeSharedAuthRepository(accessToken = null),
            accountRepository = FakeSharedAccountRepository(cachedStatus = sampleAccountStatus(), refreshResult = Result.success(sampleAccountStatus())),
            reminderRepository = reminderRepository,
            notificationScheduler = FakeSharedNotificationScheduler(enabled = false),
            exportDiagnosticsUseCase = ExportDiagnosticsUseCase(FakeSharedDiagnosticsRepository(), FakeSharedFileExporter()),
            previewDiagnosticsUseCase = PreviewDiagnosticsUseCase(FakeSharedDiagnosticsRepository())
        )

        val syncedCount = controller.syncReminders()
        val preview = controller.previewReminders()

        assertEquals(0, syncedCount)
        assertEquals(1, reminderRepository.cancelCalls)
        assertEquals(1, preview.size)
    }

    @Test
    fun `controller syncReminders refreshes and schedules when cache is empty`() = runBlocking {
        val status = sampleAccountStatus()
        val reminderRepository = FakeSharedReminderRepository(
            scheduledReminders = listOf(ScheduledReminder(Instant.parse("2026-04-20T09:00:00Z"), "Scheduled"))
        )
        val accountRepository = FakeSharedAccountRepository(cachedStatus = null, refreshResult = Result.success(status))
        val controller = CueController(
            authRepository = FakeSharedAuthRepository(accessToken = null),
            accountRepository = accountRepository,
            reminderRepository = reminderRepository,
            notificationScheduler = FakeSharedNotificationScheduler(enabled = true),
            exportDiagnosticsUseCase = ExportDiagnosticsUseCase(FakeSharedDiagnosticsRepository(), FakeSharedFileExporter()),
            previewDiagnosticsUseCase = PreviewDiagnosticsUseCase(FakeSharedDiagnosticsRepository())
        )

        val syncedCount = controller.syncReminders()

        assertEquals(1, syncedCount)
        assertEquals(1, accountRepository.refreshCalls)
    }

    @Test
    fun `controller syncReminders returns zero when refresh fails without cache`() = runBlocking {
        val accountRepository = FakeSharedAccountRepository(
            cachedStatus = null,
            refreshResult = Result.failure(IllegalStateException("refresh failed"))
        )
        val reminderRepository = FakeSharedReminderRepository()
        val controller = CueController(
            authRepository = FakeSharedAuthRepository(accessToken = null),
            accountRepository = accountRepository,
            reminderRepository = reminderRepository,
            notificationScheduler = FakeSharedNotificationScheduler(enabled = true),
            exportDiagnosticsUseCase = ExportDiagnosticsUseCase(FakeSharedDiagnosticsRepository(), FakeSharedFileExporter()),
            previewDiagnosticsUseCase = PreviewDiagnosticsUseCase(FakeSharedDiagnosticsRepository())
        )

        val syncedCount = controller.syncReminders()

        assertEquals(0, syncedCount)
        assertEquals(1, accountRepository.refreshCalls)
        assertEquals(0, reminderRepository.scheduleCalls)
    }

    @Test
    fun `controller exports and previews diagnostics`() = runBlocking {
        val diagnosticsRepository = FakeSharedDiagnosticsRepository()
        val controller = CueController(
            authRepository = FakeSharedAuthRepository(accessToken = null),
            accountRepository = FakeSharedAccountRepository(cachedStatus = sampleAccountStatus()),
            reminderRepository = FakeSharedReminderRepository(),
            notificationScheduler = FakeSharedNotificationScheduler(enabled = true),
            exportDiagnosticsUseCase = ExportDiagnosticsUseCase(diagnosticsRepository, FakeSharedFileExporter()),
            previewDiagnosticsUseCase = PreviewDiagnosticsUseCase(diagnosticsRepository)
        )

        val preview = controller.previewDiagnostics()
        val export = controller.exportDiagnostics()

        assertTrue(preview.contains("notificationsEnabled"))
        assertEquals("diagnostics.json", export.displayName)
    }

    @Test
    fun `realdebrid api retries alternate host on transport failure`() = runBlocking {
        val requestedHosts = mutableListOf<String>()
        val client = HttpClient(MockEngine { request ->
            requestedHosts += request.url.host
            when (request.url.host) {
                "api.real-debrid.com" -> throw IllegalStateException("TLS handshake failed")
                else -> respond(
                    content = """
                        {"id":1,"username":"sample-user","type":"premium","premium":432000,"expiration":"2026-04-23T09:00:00Z"}
                    """.trimIndent(),
                    status = HttpStatusCode.OK,
                    headers = headersOf("Content-Type", ContentType.Application.Json.toString())
                )
            }
        }) {
            install(ContentNegotiation) {
                json(Json { ignoreUnknownKeys = true })
            }
        }
        val api = RealDebridApi(client)

        api.getUser("token")

        assertEquals(listOf("api.real-debrid.com", "api-1.real-debrid.com"), requestedHosts)
    }

    @Test
    fun `realdebrid api does not retry non transport failures`() = runBlocking {
        val requestedHosts = mutableListOf<String>()
        val client = HttpClient(MockEngine { request ->
            requestedHosts += request.url.host
            throw IllegalStateException("authorization_pending")
        })
        val api = RealDebridApi(client)

        assertFailsWith<IllegalStateException> {
            api.getDeviceCode("client-id")
        }
        assertEquals(listOf("api.real-debrid.com"), requestedHosts)
    }

    private fun sampleAccountStatus() = AccountStatus(
        username = "sample-user",
        expiration = Instant.parse("2026-04-23T09:00:00Z"),
        remainingDays = 5,
        premiumSeconds = 432000,
        isPremium = true,
        lastCheckedAt = fixedNow,
        expiryState = ExpiryState.ACTIVE
    )
}

private class FakeSharedRealDebridService : RealDebridService {
    var userDto: UserDto? = null
    var deviceCodeResponse: DeviceCodeResponse? = null
    var credentialsResponse: DeviceCredentialsResponse? = null
    var tokenResponse: TokenResponse? = null
    var refreshFailure: Throwable? = null

    override suspend fun getUser(accessToken: String): UserDto = requireNotNull(userDto)

    override suspend fun getDeviceCode(clientId: String): DeviceCodeResponse = requireNotNull(deviceCodeResponse)

    override suspend fun getDeviceCredentials(clientId: String, deviceCode: String): DeviceCredentialsResponse = requireNotNull(credentialsResponse)

    override suspend fun exchangeToken(clientId: String, clientSecret: String, deviceCode: String): TokenResponse = requireNotNull(tokenResponse)

    override suspend fun refreshToken(clientId: String, clientSecret: String, refreshToken: String): TokenResponse {
        refreshFailure?.let { throw it }
        return requireNotNull(tokenResponse)
    }
}

private class FakeSharedAuthRepository(
    private val accessToken: String?
) : AuthRepository {
    override suspend fun startAuthorization() = error("Unused")

    override suspend fun pollAuthorization() = error("Unused")

    override suspend fun getStoredAuthState(): StoredAuthState? = null

    override suspend fun ensureValidAccessToken(): String? = accessToken

    override suspend fun isAuthenticated(): Boolean = accessToken != null

    override suspend fun disconnect() = Unit
}

private class FakeSharedSecureTokenStore : SecureTokenStore {
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

private class FakeSharedReminderConfigStore(
    private var config: ReminderConfig
) : ReminderConfigStore {
    override suspend fun read(): ReminderConfig = config

    override suspend fun write(config: ReminderConfig) {
        this.config = config
    }
}

private class FakeSharedNotificationScheduler(
    private val enabled: Boolean
) : NotificationScheduler {
    var scheduledReminders: List<ScheduledReminder> = emptyList()

    override suspend fun requestPermissionIfNeeded(): Boolean = enabled

    override suspend fun areNotificationsEnabled(): Boolean = enabled

    override suspend fun schedule(reminders: List<ScheduledReminder>) {
        scheduledReminders = reminders
    }

    override suspend fun cancelAll() = Unit
}

private class FakeSharedAccountRepository(
    private val refreshResult: Result<AccountStatus> = Result.success(
        AccountStatus(
            username = "sample-user",
            expiration = Instant.parse("2026-04-23T09:00:00Z"),
            remainingDays = 5,
            premiumSeconds = 432000,
            isPremium = true,
            lastCheckedAt = Instant.parse("2026-04-18T09:00:00Z"),
            expiryState = ExpiryState.ACTIVE
        )
    ),
    private val cachedStatus: AccountStatus? = null
) : AccountRepository {
    var refreshCalls: Int = 0

    override suspend fun refreshAccountStatus(): Result<AccountStatus> = refreshResult
        .also { refreshCalls += 1 }

    override suspend fun getCachedAccountStatus(): AccountStatus? = cachedStatus
}

private class FakeSharedReminderRepository(
    private val previewReminders: List<ScheduledReminder> = emptyList(),
    private val scheduledReminders: List<ScheduledReminder> = emptyList(),
    private val scheduleFailure: Throwable? = null
) : ReminderRepository {
    var cancelCalls: Int = 0
    var scheduleCalls: Int = 0

    override suspend fun getConfig(): ReminderConfig = ReminderConfig()

    override suspend fun updateConfig(config: ReminderConfig) = Unit

    override suspend fun previewReminders(accountStatus: AccountStatus): List<ScheduledReminder> = previewReminders

    override suspend fun scheduleReminders(accountStatus: AccountStatus): List<ScheduledReminder> {
        scheduleCalls += 1
        scheduleFailure?.let { throw it }
        return scheduledReminders
    }

    override suspend fun cancelReminders() {
        cancelCalls += 1
    }
}

private class FakeSharedDiagnosticsRepository : DiagnosticsRepository {
    override suspend fun collectDiagnostics(): DiagnosticsBundle = DiagnosticsBundle(
        appVersion = "1.0.0",
        os = "Android 16",
        lastSync = null,
        accountState = null,
        additionalInfo = mapOf("notificationsEnabled" to "true")
    )
}

private class FakeSharedFileExporter : FileExporter {
    override suspend fun exportTextFile(fileName: String, content: String): ExportedFile =
        ExportedFile(displayName = fileName, location = "/tmp/$fileName")
}
