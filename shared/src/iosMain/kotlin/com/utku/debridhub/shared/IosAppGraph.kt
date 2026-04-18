package com.utku.debridhub.shared

import com.utku.debridhub.shared.data.remote.RealDebridApi
import com.utku.debridhub.shared.data.repository.AccountRepositoryImpl
import com.utku.debridhub.shared.data.repository.AuthRepositoryImpl
import com.utku.debridhub.shared.data.repository.DiagnosticsRepositoryImpl
import com.utku.debridhub.shared.data.repository.ReminderRepositoryImpl
import com.utku.debridhub.shared.domain.usecase.ExportDiagnosticsUseCase
import com.utku.debridhub.shared.domain.usecase.PreviewDiagnosticsUseCase
import com.utku.debridhub.shared.platform.FileExporterImpl
import com.utku.debridhub.shared.platform.NotificationSchedulerImpl
import com.utku.debridhub.shared.platform.ReminderConfigStoreImpl
import com.utku.debridhub.shared.platform.SecureTokenStoreImpl
import com.utku.debridhub.shared.reminders.ReminderPlanner
import io.ktor.client.HttpClient
import io.ktor.client.engine.darwin.Darwin
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.logging.LogLevel
import io.ktor.client.plugins.logging.Logging
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json
import platform.UIKit.UIDevice

class IosAppGraph(
    appVersion: String = "1.0.0"
) {
    private val httpClient = HttpClient(Darwin) {
        engine {
            configureSession {
                // The iOS simulator inherits macOS proxy settings.
                // Force direct connections for Real-Debrid API calls so local
                // debugging proxies do not break TLS handshakes.
                connectionProxyDictionary = mapOf(
                    "HTTPEnable" to 0,
                    "HTTPSEnable" to 0
                )
            }
        }
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true })
        }
        install(Logging) {
            level = LogLevel.NONE
        }
    }

    private val notificationScheduler = NotificationSchedulerImpl()
    private val authRepository = AuthRepositoryImpl(
        api = RealDebridApi(httpClient),
        tokenStore = SecureTokenStoreImpl()
    )
    private val accountRepository = AccountRepositoryImpl(
        api = RealDebridApi(httpClient),
        authRepository = authRepository
    )
    private val reminderRepository = ReminderRepositoryImpl(
        configStore = ReminderConfigStoreImpl(),
        planner = ReminderPlanner(),
        notificationScheduler = notificationScheduler
    )
    private val diagnosticsRepository = DiagnosticsRepositoryImpl(
        appVersionProvider = { appVersion },
        osProvider = { "iOS ${UIDevice.currentDevice.systemVersion}" },
        accountRepository = accountRepository,
        additionalInfoProvider = {
            mapOf(
                "notificationsEnabled" to notificationScheduler.areNotificationsEnabled().toString()
            )
        }
    )

    val controller = DebridHubController(
        authRepository = authRepository,
        accountRepository = accountRepository,
        reminderRepository = reminderRepository,
        notificationScheduler = notificationScheduler,
        exportDiagnosticsUseCase = ExportDiagnosticsUseCase(
            diagnosticsRepository = diagnosticsRepository,
            fileExporter = FileExporterImpl()
        ),
        previewDiagnosticsUseCase = PreviewDiagnosticsUseCase(
            diagnosticsRepository = diagnosticsRepository
        )
    )

    fun close() {
        httpClient.close()
    }
}
