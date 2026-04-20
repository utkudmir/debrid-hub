package app.debridhub.android

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import app.debridhub.shared.core.RealDebridErrorMessages
import app.debridhub.shared.domain.model.AccountStatus
import app.debridhub.shared.domain.model.AuthPollResult
import app.debridhub.shared.domain.model.DeviceAuthSession
import app.debridhub.shared.domain.model.ReminderConfig
import app.debridhub.shared.domain.model.ScheduledReminder
import app.debridhub.shared.domain.repository.AccountRepository
import app.debridhub.shared.domain.repository.AuthRepository
import app.debridhub.shared.domain.repository.ReminderRepository
import app.debridhub.shared.domain.usecase.ExportDiagnosticsUseCase
import app.debridhub.shared.domain.usecase.PreviewDiagnosticsUseCase
import app.debridhub.shared.localization.AppLocalization
import app.debridhub.shared.platform.NotificationScheduler
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class OnboardingUiState(
    val isStarting: Boolean = false,
    val isPolling: Boolean = false,
    val session: DeviceAuthSession? = null
)

enum class NotificationPermissionUiState {
    Unknown,
    Granted,
    Disabled
}

data class DebridHubUiState(
    val checkingSession: Boolean = true,
    val isAuthenticated: Boolean = false,
    val isRefreshingAccount: Boolean = false,
    val isExportingDiagnostics: Boolean = false,
    val isLoadingDiagnosticsPreview: Boolean = false,
    val diagnosticsPreview: String? = null,
    val onboarding: OnboardingUiState = OnboardingUiState(),
    val accountStatus: AccountStatus? = null,
    val scheduledReminders: List<ScheduledReminder> = emptyList(),
    val reminderConfig: ReminderConfig = ReminderConfig(),
    val notificationPermissionState: NotificationPermissionUiState = NotificationPermissionUiState.Unknown,
    val infoMessage: String? = null,
    val errorMessage: String? = null
)

sealed interface DebridHubEvent {
    data class OpenUrl(val url: String) : DebridHubEvent
    data class ShareDiagnostics(val displayName: String, val location: String) : DebridHubEvent
    data object RequestNotificationPermission : DebridHubEvent
}

class DebridHubViewModel(
    private val authRepository: AuthRepository,
    private val accountRepository: AccountRepository,
    private val reminderRepository: ReminderRepository,
    private val notificationScheduler: NotificationScheduler,
    private val exportDiagnosticsUseCase: ExportDiagnosticsUseCase,
    private val previewDiagnosticsUseCase: PreviewDiagnosticsUseCase
) : ViewModel() {
    private val _uiState = MutableStateFlow(DebridHubUiState())
    val uiState = _uiState.asStateFlow()

    private val _events = MutableSharedFlow<DebridHubEvent>(extraBufferCapacity = 8)
    val events = _events.asSharedFlow()

    private var authPollingJob: Job? = null

    init {
        viewModelScope.launch {
            val reminderConfig = reminderRepository.getConfig()
            val notificationsEnabled = notificationScheduler.areNotificationsEnabled()
            _uiState.update {
                it.copy(
                    reminderConfig = reminderConfig,
                    notificationPermissionState = notificationsEnabled.toPermissionState()
                )
            }
            val authenticated = authRepository.isAuthenticated()
            _uiState.update {
                it.copy(
                    checkingSession = false,
                    isAuthenticated = authenticated
                )
            }
            if (authenticated) {
                refreshAccountStatus()
            }
        }
    }

    fun startAuthorization() {
        if (_uiState.value.onboarding.isStarting || _uiState.value.onboarding.isPolling) return
        viewModelScope.launch {
            _uiState.update { it.copy(errorMessage = null, onboarding = OnboardingUiState(isStarting = true)) }
            runCatching { authRepository.startAuthorization() }
                .onSuccess { session ->
                    _uiState.update {
                        it.copy(
                            onboarding = OnboardingUiState(
                                isStarting = false,
                                isPolling = true,
                                session = session
                            )
                        )
                    }
                    _events.tryEmit(
                        DebridHubEvent.OpenUrl(
                            session.directVerificationUrl ?: session.verificationUrl
                        )
                    )
                    beginPolling(session)
                }
                .onFailure { throwable ->
                    _uiState.update {
                        it.copy(
                            onboarding = OnboardingUiState(),
                            errorMessage = throwable.presentableMessage("messages.unable_start_authorization"),
                            infoMessage = null
                        )
                    }
                }
        }
    }

    fun cancelAuthorization() {
        authPollingJob?.cancel()
        _uiState.update { it.copy(onboarding = OnboardingUiState()) }
    }

    fun refreshAccountStatus() {
        viewModelScope.launch {
            _uiState.update { it.copy(isRefreshingAccount = true, errorMessage = null) }
            accountRepository.refreshAccountStatus()
                .onSuccess { status ->
                    _uiState.update {
                        it.copy(
                            isAuthenticated = true,
                            isRefreshingAccount = false,
                            accountStatus = status
                        )
                    }
                    syncReminders(status)
                }
                .onFailure { throwable ->
                    _uiState.update {
                        it.copy(
                            isRefreshingAccount = false,
                            errorMessage = throwable.presentableMessage("messages.unable_refresh_account"),
                            infoMessage = null
                        )
                    }
                }
        }
    }

    fun onNotificationPermissionResult(granted: Boolean) {
        viewModelScope.launch {
            val notificationsEnabled = notificationScheduler.areNotificationsEnabled()
            _uiState.update { it.copy(notificationPermissionState = notificationsEnabled.toPermissionState()) }
            if (!granted) {
                showInfoKey("messages.notifications_still_disabled")
                _uiState.value.accountStatus?.let { refreshReminderPreview(it) }
                return@launch
            }
            showInfoKey("messages.notifications_enabled")
            _uiState.value.accountStatus?.let { syncReminders(it) }
        }
    }

    fun requestNotificationPermission() {
        viewModelScope.launch {
            val notificationsEnabled = notificationScheduler.areNotificationsEnabled()
            _uiState.update { it.copy(notificationPermissionState = notificationsEnabled.toPermissionState()) }
            if (notificationsEnabled) {
                showInfoKey("onboarding.notifications_already_enabled")
                _uiState.value.accountStatus?.let { syncReminders(it) }
            } else {
                _events.emit(DebridHubEvent.RequestNotificationPermission)
            }
        }
    }

    fun setReminderEnabled(enabled: Boolean) {
        mutateReminderConfig { copy(enabled = enabled) }
    }

    fun toggleReminderDay(day: Int) {
        if (day !in setOf(1, 3, 7)) return
        mutateReminderConfig {
            val nextDays = if (daysBefore.contains(day)) daysBefore - day else daysBefore + day
            copy(daysBefore = nextDays)
        }
    }

    fun setNotifyOnExpiry(enabled: Boolean) {
        mutateReminderConfig { copy(notifyOnExpiry = enabled) }
    }

    fun setNotifyAfterExpiry(enabled: Boolean) {
        mutateReminderConfig { copy(notifyAfterExpiry = enabled) }
    }

    fun exportDiagnostics() {
        viewModelScope.launch {
            _uiState.update { it.copy(isExportingDiagnostics = true) }
            exportDiagnosticsUseCase()
                .onSuccess { exportedFile ->
                    showInfo(AppLocalization.text("messages.diagnostics_exported", exportedFile.location))
                    _events.emit(
                        DebridHubEvent.ShareDiagnostics(
                            displayName = exportedFile.displayName,
                            location = exportedFile.location
                        )
                    )
                }
                .onFailure { throwable ->
                    _uiState.update {
                        it.copy(
                            errorMessage = throwable.presentableMessage("messages.unable_export_diagnostics"),
                            infoMessage = null
                        )
                    }
                }
            _uiState.update { it.copy(isExportingDiagnostics = false) }
        }
    }

    fun loadDiagnosticsPreview() {
        if (_uiState.value.isLoadingDiagnosticsPreview) return
        _uiState.update { it.copy(isLoadingDiagnosticsPreview = true) }
        viewModelScope.launch {
            previewDiagnosticsUseCase()
                .onSuccess { preview ->
                    _uiState.update {
                        it.copy(
                            isLoadingDiagnosticsPreview = false,
                            diagnosticsPreview = preview
                        )
                    }
                }
                .onFailure { throwable ->
                    _uiState.update {
                        it.copy(
                            isLoadingDiagnosticsPreview = false,
                            errorMessage = throwable.presentableMessage("messages.unable_load_diagnostics_preview"),
                            infoMessage = null
                        )
                    }
                }
        }
    }

    fun disconnect() {
        authPollingJob?.cancel()
        viewModelScope.launch {
            authRepository.disconnect()
            reminderRepository.cancelReminders()
            _uiState.value = DebridHubUiState(
                checkingSession = false,
                reminderConfig = reminderRepository.getConfig(),
                infoMessage = AppLocalization.text("messages.disconnected")
            )
        }
    }

    private fun beginPolling(session: DeviceAuthSession) {
        authPollingJob?.cancel()
        authPollingJob = viewModelScope.launch {
            while (true) {
                when (val result = authRepository.pollAuthorization()) {
                    AuthPollResult.Pending -> delay(session.pollIntervalSeconds * 1000)
                    is AuthPollResult.Authorized -> {
                        _uiState.update {
                            it.copy(
                                isAuthenticated = true,
                                onboarding = OnboardingUiState(),
                                infoMessage = AppLocalization.text("messages.authorization_completed"),
                                errorMessage = null
                            )
                        }
                        refreshAccountStatus()
                        return@launch
                    }
                    AuthPollResult.Expired -> {
                        _uiState.update {
                            it.copy(
                                onboarding = OnboardingUiState(),
                                errorMessage = AppLocalization.text("messages.authorization_expired"),
                                infoMessage = null
                            )
                        }
                        return@launch
                    }
                    AuthPollResult.Denied -> {
                        _uiState.update {
                            it.copy(
                                onboarding = OnboardingUiState(),
                                errorMessage = AppLocalization.text("messages.authorization_denied"),
                                infoMessage = null
                            )
                        }
                        return@launch
                    }
                    is AuthPollResult.Failure -> {
                        _uiState.update {
                            it.copy(
                                onboarding = OnboardingUiState(),
                                errorMessage = result.message,
                                infoMessage = null
                            )
                        }
                        return@launch
                    }
                }
            }
        }
    }

    private fun mutateReminderConfig(transform: ReminderConfig.() -> ReminderConfig) {
        viewModelScope.launch {
            val updated = _uiState.value.reminderConfig.transform()
            reminderRepository.updateConfig(updated)
            _uiState.update { it.copy(reminderConfig = updated, errorMessage = null) }
            _uiState.value.accountStatus?.let { syncReminders(it) }
        }
    }

    private suspend fun syncReminders(status: AccountStatus) {
        val config = reminderRepository.getConfig()
        val preview = reminderRepository.previewReminders(status)
        val notificationsEnabled = notificationScheduler.areNotificationsEnabled()
        _uiState.update {
            it.copy(
                reminderConfig = config,
                scheduledReminders = preview,
                notificationPermissionState = notificationsEnabled.toPermissionState()
            )
        }
        if (!config.enabled) {
            reminderRepository.cancelReminders()
            return
        }
        if (!notificationsEnabled) {
            reminderRepository.cancelReminders()
            return
        }
        val reminders = reminderRepository.scheduleReminders(status)
        _uiState.update { it.copy(scheduledReminders = reminders) }
    }

    private suspend fun refreshReminderPreview(status: AccountStatus) {
        val config = reminderRepository.getConfig()
        val preview = reminderRepository.previewReminders(status)
        val notificationsEnabled = notificationScheduler.areNotificationsEnabled()
        _uiState.update {
            it.copy(
                reminderConfig = config,
                scheduledReminders = preview,
                notificationPermissionState = notificationsEnabled.toPermissionState()
            )
        }
    }

    private fun Throwable.presentableMessage(fallback: String): String {
        val details = generateSequence(this) { it.cause }
            .mapNotNull { it.message?.trim()?.takeIf(String::isNotEmpty) }
            .distinct()
            .joinToString(separator = " | ")
        return RealDebridErrorMessages.presentableMessage(details, AppLocalization.text(fallback))
    }

    private fun showInfo(message: String) {
        _uiState.update {
            it.copy(
                infoMessage = message,
                errorMessage = null
            )
        }
    }

    private fun showInfoKey(key: String) {
        showInfo(AppLocalization.text(key))
    }

    private fun Boolean.toPermissionState(): NotificationPermissionUiState =
        if (this) NotificationPermissionUiState.Granted else NotificationPermissionUiState.Disabled
}

class DebridHubViewModelFactory(
    private val graph: AndroidAppGraph
) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(DebridHubViewModel::class.java)) {
            @Suppress("UNCHECKED_CAST")
            return DebridHubViewModel(
                authRepository = graph.authRepository,
                accountRepository = graph.accountRepository,
                reminderRepository = graph.reminderRepository,
                notificationScheduler = graph.notificationScheduler,
                exportDiagnosticsUseCase = graph.exportDiagnosticsUseCase,
                previewDiagnosticsUseCase = graph.previewDiagnosticsUseCase
            ) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class: ${modelClass.name}")
    }
}
