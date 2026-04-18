package app.debridhub.android

import app.debridhub.shared.domain.model.AccountStatus
import app.debridhub.shared.domain.model.AuthPollResult
import app.debridhub.shared.domain.model.DeviceAuthSession
import app.debridhub.shared.domain.model.DiagnosticsBundle
import app.debridhub.shared.domain.model.ExpiryState
import app.debridhub.shared.domain.model.ReminderConfig
import app.debridhub.shared.domain.model.ScheduledReminder
import app.debridhub.shared.domain.model.StoredAuthState
import app.debridhub.shared.domain.repository.AccountRepository
import app.debridhub.shared.domain.repository.AuthRepository
import app.debridhub.shared.domain.repository.DiagnosticsRepository
import app.debridhub.shared.domain.repository.ReminderRepository
import app.debridhub.shared.domain.usecase.ExportDiagnosticsUseCase
import app.debridhub.shared.domain.usecase.PreviewDiagnosticsUseCase
import app.debridhub.shared.platform.ExportedFile
import app.debridhub.shared.platform.FileExporter
import app.debridhub.shared.platform.NotificationScheduler
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DebridHubViewModelTest {
    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    @Test
    fun `init loads local session state and notification status`() = runTest {
        val reminderConfig = ReminderConfig(enabled = false, daysBefore = setOf(3))
        val viewModel = buildViewModel(
            authRepository = FakeAuthRepository(isAuthenticated = false),
            reminderRepository = FakeReminderRepository(config = reminderConfig),
            notificationScheduler = FakeNotificationScheduler(enabled = false)
        )

        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.checkingSession)
        assertFalse(state.isAuthenticated)
        assertEquals(reminderConfig, state.reminderConfig)
        assertEquals(NotificationPermissionUiState.Disabled, state.notificationPermissionState)
    }

    @Test
    fun `init with authenticated session refreshes account and reminders`() = runTest {
        val status = sampleAccountStatus()
        val scheduled = listOf(
            ScheduledReminder(Instant.parse("2026-04-20T09:00:00Z"), "3 days left"),
            ScheduledReminder(Instant.parse("2026-04-22T09:00:00Z"), "1 day left")
        )
        val accountRepository = FakeAccountRepository(refreshResult = Result.success(status))
        val reminderRepository = FakeReminderRepository(
            preview = listOf(ScheduledReminder(Instant.parse("2026-04-19T09:00:00Z"), "preview")),
            scheduled = scheduled
        )
        val viewModel = buildViewModel(
            authRepository = FakeAuthRepository(isAuthenticated = true),
            accountRepository = accountRepository,
            reminderRepository = reminderRepository,
            notificationScheduler = FakeNotificationScheduler(enabled = true)
        )

        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.checkingSession)
        assertTrue(state.isAuthenticated)
        assertEquals(status, state.accountStatus)
        assertEquals(scheduled, state.scheduledReminders)
        assertEquals(1, accountRepository.refreshCallCount)
        assertEquals(1, reminderRepository.scheduleCallCount)
    }

    @Test
    fun `refresh account status schedules reminders when notifications are enabled`() = runTest {
        val status = sampleAccountStatus()
        val scheduled = listOf(
            ScheduledReminder(Instant.parse("2026-04-20T09:00:00Z"), "3 days left"),
            ScheduledReminder(Instant.parse("2026-04-22T09:00:00Z"), "1 day left")
        )
        val reminderRepository = FakeReminderRepository(
            preview = listOf(ScheduledReminder(Instant.parse("2026-04-19T09:00:00Z"), "preview")),
            scheduled = scheduled
        )
        val viewModel = buildViewModel(
            authRepository = FakeAuthRepository(isAuthenticated = false),
            accountRepository = FakeAccountRepository(refreshResult = Result.success(status)),
            reminderRepository = reminderRepository,
            notificationScheduler = FakeNotificationScheduler(enabled = true)
        )

        advanceUntilIdle()
        viewModel.refreshAccountStatus()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue(state.isAuthenticated)
        assertEquals(status, state.accountStatus)
        assertEquals(scheduled, state.scheduledReminders)
        assertEquals(1, reminderRepository.scheduleCallCount)
    }

    @Test
    fun `disconnect clears auth state and cancels reminders`() = runTest {
        val reminderRepository = FakeReminderRepository(config = ReminderConfig(enabled = true, daysBefore = setOf(7, 1)))
        val authRepository = FakeAuthRepository(isAuthenticated = false)
        val viewModel = buildViewModel(
            authRepository = authRepository,
            reminderRepository = reminderRepository,
            notificationScheduler = FakeNotificationScheduler(enabled = true)
        )

        advanceUntilIdle()
        viewModel.disconnect()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isAuthenticated)
        assertFalse(state.checkingSession)
        assertEquals(reminderRepository.config, state.reminderConfig)
        assertTrue(authRepository.disconnectCalled)
        assertEquals(1, reminderRepository.cancelCallCount)
        assertEquals("Disconnected from Real-Debrid.", state.infoMessage)
    }

    @Test
    fun `start authorization failure surfaces presentable error`() = runTest {
        val viewModel = buildViewModel(
            authRepository = FakeAuthRepository(
                startAuthorizationResult = Result.failure(IllegalStateException("authorization_pending"))
            )
        )

        advanceUntilIdle()

        viewModel.startAuthorization()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.onboarding.isStarting)
        assertFalse(state.onboarding.isPolling)
        assertEquals("authorization_pending", state.errorMessage)
    }

    @Test
    fun `request notification permission emits system prompt event when disabled`() = runTest {
        val viewModel = buildViewModel(
            notificationScheduler = FakeNotificationScheduler(enabled = false)
        )

        advanceUntilIdle()
        val eventDeferred = async { viewModel.events.first() }

        viewModel.requestNotificationPermission()
        advanceUntilIdle()

        assertEquals(DebridHubEvent.RequestNotificationPermission, eventDeferred.await())
        assertEquals(NotificationPermissionUiState.Disabled, viewModel.uiState.value.notificationPermissionState)
    }

    @Test
    fun `request notification permission surfaces info when already enabled`() = runTest {
        val viewModel = buildViewModel(
            notificationScheduler = FakeNotificationScheduler(enabled = true)
        )

        advanceUntilIdle()
        viewModel.requestNotificationPermission()
        advanceUntilIdle()

        assertEquals("Notifications are already enabled.", viewModel.uiState.value.infoMessage)
        assertEquals(NotificationPermissionUiState.Granted, viewModel.uiState.value.notificationPermissionState)
    }

    @Test
    fun `notification denial keeps reminders unscheduled and emits guidance`() = runTest {
        val status = sampleAccountStatus()
        val preview = listOf(ScheduledReminder(Instant.parse("2026-04-20T09:00:00Z"), "preview"))
        val reminderRepository = FakeReminderRepository(preview = preview)
        val viewModel = buildViewModel(
            accountRepository = FakeAccountRepository(refreshResult = Result.success(status)),
            reminderRepository = reminderRepository,
            notificationScheduler = FakeNotificationScheduler(enabled = false)
        )

        advanceUntilIdle()
        viewModel.refreshAccountStatus()
        advanceUntilIdle()
        viewModel.onNotificationPermissionResult(granted = false)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertEquals(preview, state.scheduledReminders)
        assertEquals(0, reminderRepository.scheduleCallCount)
        assertEquals(2, reminderRepository.previewCallCount)
        assertEquals("Notifications remain disabled. Open system settings if you want reminder alerts.", state.infoMessage)
    }

    @Test
    fun `refresh failure keeps loading false and maps error message`() = runTest {
        val viewModel = buildViewModel(
            accountRepository = FakeAccountRepository(
                refreshResult = Result.failure(IllegalStateException("Unable to resolve host api.real-debrid.com"))
            )
        )

        advanceUntilIdle()
        viewModel.refreshAccountStatus()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isRefreshingAccount)
        assertEquals(
            "Couldn't reach Real-Debrid. Check your internet connection or try a different network.",
            state.errorMessage
        )
    }

    @Test
    fun `disabling reminders cancels scheduled notifications for authenticated account`() = runTest {
        val status = sampleAccountStatus()
        val scheduled = listOf(ScheduledReminder(Instant.parse("2026-04-20T09:00:00Z"), "scheduled"))
        val reminderRepository = FakeReminderRepository(scheduled = scheduled)
        val viewModel = buildViewModel(
            accountRepository = FakeAccountRepository(refreshResult = Result.success(status)),
            reminderRepository = reminderRepository,
            notificationScheduler = FakeNotificationScheduler(enabled = true)
        )

        advanceUntilIdle()
        viewModel.refreshAccountStatus()
        advanceUntilIdle()

        viewModel.setReminderEnabled(false)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.reminderConfig.enabled)
        assertEquals(1, reminderRepository.scheduleCallCount)
        assertEquals(1, reminderRepository.cancelCallCount)
    }

    @Test
    fun `start authorization opens browser and completes after pending poll result`() = runTest {
        val session = DeviceAuthSession(
            userCode = "ABCD-EFGH",
            verificationUrl = "https://real-debrid.com/device",
            directVerificationUrl = "https://real-debrid.com/device/direct",
            pollIntervalSeconds = 0,
            expiresAt = Instant.parse("2026-04-18T10:00:00Z")
        )
        val openUrlDeferred = async {
            buildViewModel(
                authRepository = FakeAuthRepository(
                    startAuthorizationResult = Result.success(session),
                    pollResults = ArrayDeque(
                        listOf(
                            AuthPollResult.Pending,
                            AuthPollResult.Authorized(sampleStoredAuthState())
                        )
                    )
                ),
                accountRepository = FakeAccountRepository(refreshResult = Result.success(sampleAccountStatus())),
                reminderRepository = FakeReminderRepository(config = ReminderConfig(enabled = false)),
                notificationScheduler = FakeNotificationScheduler(enabled = false)
            )
        }

        val viewModel = openUrlDeferred.await()
        advanceUntilIdle()

        val openUrlEvent = async { viewModel.events.first { it is DebridHubEvent.OpenUrl } }
        viewModel.startAuthorization()
        advanceUntilIdle()

        assertEquals(
            DebridHubEvent.OpenUrl("https://real-debrid.com/device/direct"),
            openUrlEvent.await()
        )
        assertTrue(viewModel.uiState.value.isAuthenticated)
        assertEquals(OnboardingUiState(), viewModel.uiState.value.onboarding)
        assertEquals(sampleAccountStatus(), viewModel.uiState.value.accountStatus)
        assertEquals("Authorization completed.", viewModel.uiState.value.infoMessage)
    }

    @Test
    fun `polling expiry clears onboarding and surfaces expiration message`() = runTest {
        val session = DeviceAuthSession(
            userCode = "ABCD-EFGH",
            verificationUrl = "https://real-debrid.com/device",
            pollIntervalSeconds = 0,
            expiresAt = Instant.parse("2026-04-18T10:00:00Z")
        )
        val viewModel = buildViewModel(
            authRepository = FakeAuthRepository(
                startAuthorizationResult = Result.success(session),
                pollResults = ArrayDeque(listOf(AuthPollResult.Expired))
            )
        )

        advanceUntilIdle()
        val openUrlEvent = async { viewModel.events.firstOrNull { it is DebridHubEvent.OpenUrl } }

        viewModel.startAuthorization()
        advanceUntilIdle()

        assertEquals(
            DebridHubEvent.OpenUrl("https://real-debrid.com/device"),
            openUrlEvent.await()
        )
        assertEquals(OnboardingUiState(), viewModel.uiState.value.onboarding)
        assertEquals(
            "The device authorization session expired. Start again.",
            viewModel.uiState.value.errorMessage
        )
    }

    @Test
    fun `polling denial clears onboarding and surfaces denied message`() = runTest {
        val session = DeviceAuthSession(
            userCode = "ABCD-EFGH",
            verificationUrl = "https://real-debrid.com/device",
            pollIntervalSeconds = 0,
            expiresAt = Instant.parse("2026-04-18T10:00:00Z")
        )
        val viewModel = buildViewModel(
            authRepository = FakeAuthRepository(
                startAuthorizationResult = Result.success(session),
                pollResults = ArrayDeque(listOf(AuthPollResult.Denied))
            )
        )

        advanceUntilIdle()

        viewModel.startAuthorization()
        advanceUntilIdle()

        assertEquals(OnboardingUiState(), viewModel.uiState.value.onboarding)
        assertEquals(
            "Real-Debrid denied the authorization request.",
            viewModel.uiState.value.errorMessage
        )
    }

    @Test
    fun `polling failure clears onboarding and surfaces repository message`() = runTest {
        val session = DeviceAuthSession(
            userCode = "ABCD-EFGH",
            verificationUrl = "https://real-debrid.com/device",
            pollIntervalSeconds = 0,
            expiresAt = Instant.parse("2026-04-18T10:00:00Z")
        )
        val viewModel = buildViewModel(
            authRepository = FakeAuthRepository(
                startAuthorizationResult = Result.success(session),
                pollResults = ArrayDeque(listOf(AuthPollResult.Failure(code = "temporary_error", message = "Temporary authorization outage")))
            )
        )

        advanceUntilIdle()

        viewModel.startAuthorization()
        advanceUntilIdle()

        assertEquals(OnboardingUiState(), viewModel.uiState.value.onboarding)
        assertEquals("Temporary authorization outage", viewModel.uiState.value.errorMessage)
    }

    @Test
    fun `cancel authorization stops polling and keeps user unauthenticated`() = runTest {
        val session = DeviceAuthSession(
            userCode = "ABCD-EFGH",
            verificationUrl = "https://real-debrid.com/device",
            directVerificationUrl = "https://real-debrid.com/device/direct",
            pollIntervalSeconds = 30,
            expiresAt = Instant.parse("2026-04-18T10:00:00Z")
        )
        val authRepository = FakeAuthRepository(
            startAuthorizationResult = Result.success(session),
            pollResults = ArrayDeque(
                listOf(
                    AuthPollResult.Pending,
                    AuthPollResult.Authorized(sampleStoredAuthState())
                )
            )
        )
        val viewModel = buildViewModel(authRepository = authRepository)

        advanceUntilIdle()
        viewModel.startAuthorization()
        runCurrent()

        assertTrue(viewModel.uiState.value.onboarding.isPolling)
        viewModel.cancelAuthorization()
        runCurrent()
        advanceTimeBy(31_000)
        runCurrent()

        assertEquals(OnboardingUiState(), viewModel.uiState.value.onboarding)
        assertFalse(viewModel.uiState.value.isAuthenticated)
        assertEquals(1, authRepository.pollCallCount)
    }

    @Test
    fun `export diagnostics emits share event and info message`() = runTest {
        val viewModel = buildViewModel()

        advanceUntilIdle()
        val shareEvent = async { viewModel.events.first { it is DebridHubEvent.ShareDiagnostics } }

        viewModel.exportDiagnostics()
        advanceUntilIdle()

        assertEquals(
            DebridHubEvent.ShareDiagnostics("diagnostics.json", "/tmp/diagnostics.json"),
            shareEvent.await()
        )
        assertEquals("Diagnostics exported to /tmp/diagnostics.json", viewModel.uiState.value.infoMessage)
    }

    @Test
    fun `export diagnostics failure surfaces error message`() = runTest {
        val viewModel = buildViewModel(fileExporter = FakeFileExporter(failure = IllegalStateException("disk full")))

        advanceUntilIdle()
        viewModel.exportDiagnostics()
        advanceUntilIdle()

        assertEquals("disk full", viewModel.uiState.value.errorMessage)
    }

    @Test
    fun `load diagnostics preview failure surfaces error message`() = runTest {
        val viewModel = buildViewModel(
            diagnosticsRepository = FakeDiagnosticsRepository(failure = IllegalStateException("preview unavailable"))
        )

        advanceUntilIdle()
        viewModel.loadDiagnosticsPreview()
        advanceUntilIdle()

        assertEquals("preview unavailable", viewModel.uiState.value.errorMessage)
        assertFalse(viewModel.uiState.value.isLoadingDiagnosticsPreview)
    }

    @Test
    fun `load diagnostics preview success sets preview content`() = runTest {
        val viewModel = buildViewModel()

        advanceUntilIdle()
        viewModel.loadDiagnosticsPreview()
        advanceUntilIdle()

        assertTrue(viewModel.uiState.value.diagnosticsPreview?.contains("Android 16") == true)
        assertFalse(viewModel.uiState.value.isLoadingDiagnosticsPreview)
        assertEquals(null, viewModel.uiState.value.errorMessage)
    }

    private fun buildViewModel(
        authRepository: FakeAuthRepository = FakeAuthRepository(),
        accountRepository: FakeAccountRepository = FakeAccountRepository(),
        reminderRepository: FakeReminderRepository = FakeReminderRepository(),
        notificationScheduler: FakeNotificationScheduler = FakeNotificationScheduler(),
        diagnosticsRepository: FakeDiagnosticsRepository = FakeDiagnosticsRepository(),
        fileExporter: FakeFileExporter = FakeFileExporter()
    ): DebridHubViewModel {
        return DebridHubViewModel(
            authRepository = authRepository,
            accountRepository = accountRepository,
            reminderRepository = reminderRepository,
            notificationScheduler = notificationScheduler,
            exportDiagnosticsUseCase = ExportDiagnosticsUseCase(diagnosticsRepository, fileExporter),
            previewDiagnosticsUseCase = PreviewDiagnosticsUseCase(diagnosticsRepository)
        )
    }

    private fun sampleAccountStatus() = AccountStatus(
        username = "sample-user",
        expiration = Instant.parse("2026-04-23T09:00:00Z"),
        remainingDays = 5,
        premiumSeconds = 432000,
        isPremium = true,
        lastCheckedAt = Instant.parse("2026-04-18T09:00:00Z"),
        expiryState = ExpiryState.ACTIVE
    )

    private fun sampleStoredAuthState() = StoredAuthState(
        accessToken = "access-token",
        refreshToken = "refresh-token",
        clientId = "client-id",
        clientSecret = "client-secret",
        accessTokenExpiresAt = Instant.parse("2026-04-18T12:00:00Z")
    )

    private class FakeAuthRepository(
        private val isAuthenticated: Boolean = false,
        private val startAuthorizationResult: Result<DeviceAuthSession> = Result.failure(IllegalStateException("unused")),
        private val pollResults: ArrayDeque<AuthPollResult> = ArrayDeque()
    ) : AuthRepository {
        var disconnectCalled = false
        var pollCallCount = 0

        override suspend fun startAuthorization(): DeviceAuthSession = startAuthorizationResult.getOrThrow()

        override suspend fun pollAuthorization(): AuthPollResult =
            pollResults.removeFirstOrNull()?.also { pollCallCount += 1 } ?: error("unused")

        override suspend fun getStoredAuthState(): StoredAuthState? = null

        override suspend fun ensureValidAccessToken(): String? = null

        override suspend fun isAuthenticated(): Boolean = isAuthenticated

        override suspend fun disconnect() {
            disconnectCalled = true
        }
    }

    private class FakeAccountRepository(
        var refreshResult: Result<AccountStatus> = Result.failure(IllegalStateException("unused")),
        private val cachedStatus: AccountStatus? = null
    ) : AccountRepository {
        var refreshCallCount = 0

        override suspend fun refreshAccountStatus(): Result<AccountStatus> {
            refreshCallCount += 1
            return refreshResult
        }

        override suspend fun getCachedAccountStatus(): AccountStatus? = cachedStatus
    }

    private class FakeReminderRepository(
        var config: ReminderConfig = ReminderConfig(),
        private val preview: List<ScheduledReminder> = emptyList(),
        private val scheduled: List<ScheduledReminder> = emptyList()
    ) : ReminderRepository {
        var cancelCallCount = 0
        var scheduleCallCount = 0
        var previewCallCount = 0

        override suspend fun getConfig(): ReminderConfig = config

        override suspend fun updateConfig(config: ReminderConfig) {
            this.config = config
        }

        override suspend fun previewReminders(accountStatus: AccountStatus): List<ScheduledReminder> {
            previewCallCount += 1
            return preview
        }

        override suspend fun scheduleReminders(accountStatus: AccountStatus): List<ScheduledReminder> {
            scheduleCallCount += 1
            return scheduled
        }

        override suspend fun cancelReminders() {
            cancelCallCount += 1
        }
    }

    private class FakeNotificationScheduler(
        private val enabled: Boolean = false
    ) : NotificationScheduler {
        override suspend fun requestPermissionIfNeeded(): Boolean = enabled

        override suspend fun areNotificationsEnabled(): Boolean = enabled

        override suspend fun schedule(reminders: List<ScheduledReminder>) = Unit

        override suspend fun cancelAll() = Unit
    }

    private class FakeDiagnosticsRepository(
        private val bundle: DiagnosticsBundle = DiagnosticsBundle(
            appVersion = "1.0.0",
            os = "Android 16",
            lastSync = null,
            accountState = null,
            additionalInfo = emptyMap()
        ),
        private val failure: Throwable? = null
    ) : DiagnosticsRepository {
        override suspend fun collectDiagnostics(): DiagnosticsBundle {
            failure?.let { throw it }
            return bundle
        }
    }

    private class FakeFileExporter(
        private val failure: Throwable? = null
    ) : FileExporter {
        override suspend fun exportTextFile(fileName: String, content: String): ExportedFile {
            failure?.let { throw it }
            return ExportedFile(displayName = fileName, location = "/tmp/$fileName")
        }
    }
}
