package com.utku.debridhub.shared

import com.utku.debridhub.shared.domain.model.AccountStatus
import com.utku.debridhub.shared.domain.model.AuthPollResult
import com.utku.debridhub.shared.domain.model.DeviceAuthSession
import com.utku.debridhub.shared.domain.model.ReminderConfig
import com.utku.debridhub.shared.domain.model.ReminderConfigSnapshot
import com.utku.debridhub.shared.domain.model.ScheduledReminder
import com.utku.debridhub.shared.domain.model.toReminderConfig
import com.utku.debridhub.shared.domain.model.toSnapshot
import com.utku.debridhub.shared.domain.repository.AccountRepository
import com.utku.debridhub.shared.domain.repository.AuthRepository
import com.utku.debridhub.shared.domain.repository.ReminderRepository
import com.utku.debridhub.shared.domain.usecase.ExportDiagnosticsUseCase
import com.utku.debridhub.shared.domain.usecase.PreviewDiagnosticsUseCase
import com.utku.debridhub.shared.platform.ExportedFile
import com.utku.debridhub.shared.platform.NotificationScheduler
import kotlin.Throws

class DebridHubController(
    private val authRepository: AuthRepository,
    private val accountRepository: AccountRepository,
    private val reminderRepository: ReminderRepository,
    private val notificationScheduler: NotificationScheduler,
    private val exportDiagnosticsUseCase: ExportDiagnosticsUseCase,
    private val previewDiagnosticsUseCase: PreviewDiagnosticsUseCase
) {
    @Throws(Throwable::class)
    suspend fun isAuthenticated(): Boolean = authRepository.isAuthenticated()

    @Throws(Throwable::class)
    suspend fun startAuthorization(): DeviceAuthSession = authRepository.startAuthorization()

    @Throws(Throwable::class)
    suspend fun pollAuthorization(): AuthPollResult = authRepository.pollAuthorization()

    @Throws(Throwable::class)
    suspend fun refreshAccountStatus(): AccountStatus =
        accountRepository.refreshAccountStatus().getOrThrow()

    @Throws(Throwable::class)
    suspend fun getReminderConfig(): ReminderConfig = reminderRepository.getConfig()

    @Throws(Throwable::class)
    suspend fun updateReminderConfig(config: ReminderConfig) {
        reminderRepository.updateConfig(config)
    }

    @Throws(Throwable::class)
    suspend fun getReminderConfigSnapshot(): ReminderConfigSnapshot =
        reminderRepository.getConfig().toSnapshot()

    @Throws(Throwable::class)
    suspend fun updateReminderConfigSnapshot(snapshot: ReminderConfigSnapshot) {
        reminderRepository.updateConfig(snapshot.toReminderConfig())
    }

    @Throws(Throwable::class)
    suspend fun requestNotificationPermission(): Boolean =
        notificationScheduler.requestPermissionIfNeeded()

    @Throws(Throwable::class)
    suspend fun notificationsEnabled(): Boolean =
        notificationScheduler.areNotificationsEnabled()

    @Throws(Throwable::class)
    suspend fun syncReminders(): Int {
        val status = accountRepository.getCachedAccountStatus()
            ?: accountRepository.refreshAccountStatus().getOrNull()
            ?: return 0
        if (!notificationScheduler.areNotificationsEnabled()) {
            reminderRepository.cancelReminders()
            return 0
        }
        return reminderRepository.scheduleReminders(status).size
    }

    @Throws(Throwable::class)
    suspend fun previewReminders(): List<ScheduledReminder> {
        val status = accountRepository.getCachedAccountStatus()
            ?: accountRepository.refreshAccountStatus().getOrThrow()
        return reminderRepository.previewReminders(status)
    }

    @Throws(Throwable::class)
    suspend fun exportDiagnostics(): ExportedFile =
        exportDiagnosticsUseCase().getOrThrow()

    @Throws(Throwable::class)
    suspend fun previewDiagnostics(): String =
        previewDiagnosticsUseCase().getOrThrow()

    @Throws(Throwable::class)
    suspend fun disconnect() {
        authRepository.disconnect()
        reminderRepository.cancelReminders()
    }
}
