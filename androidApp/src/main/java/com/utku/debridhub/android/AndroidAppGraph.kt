package com.utku.debridhub.android

import android.content.Context
import android.os.Build
import com.utku.debridhub.shared.data.remote.RealDebridApi
import com.utku.debridhub.shared.data.repository.AccountRepositoryImpl
import com.utku.debridhub.shared.data.repository.AuthRepositoryImpl
import com.utku.debridhub.shared.data.repository.DiagnosticsRepositoryImpl
import com.utku.debridhub.shared.data.repository.ReminderRepositoryImpl
import com.utku.debridhub.shared.domain.repository.AccountRepository
import com.utku.debridhub.shared.domain.repository.AuthRepository
import com.utku.debridhub.shared.domain.repository.DiagnosticsRepository
import com.utku.debridhub.shared.domain.repository.ReminderRepository
import com.utku.debridhub.shared.domain.usecase.ExportDiagnosticsUseCase
import com.utku.debridhub.shared.domain.usecase.PreviewDiagnosticsUseCase
import com.utku.debridhub.shared.platform.FileExporter
import com.utku.debridhub.shared.platform.FileExporterImpl
import com.utku.debridhub.shared.platform.NotificationScheduler
import com.utku.debridhub.shared.platform.NotificationSchedulerImpl
import com.utku.debridhub.shared.platform.ReminderConfigStore
import com.utku.debridhub.shared.platform.ReminderConfigStoreImpl
import com.utku.debridhub.shared.platform.SecureTokenStore
import com.utku.debridhub.shared.platform.SecureTokenStoreImpl
import com.utku.debridhub.shared.reminders.ReminderPlanner
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.logging.LogLevel
import io.ktor.client.plugins.logging.Logging
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json
import java.net.Proxy

data class AndroidAppGraph(
    val authRepository: AuthRepository,
    val accountRepository: AccountRepository,
    val reminderRepository: ReminderRepository,
    val notificationScheduler: NotificationScheduler,
    val exportDiagnosticsUseCase: ExportDiagnosticsUseCase,
    val previewDiagnosticsUseCase: PreviewDiagnosticsUseCase
)

fun buildAndroidAppGraph(context: Context): AndroidAppGraph {
    val appContext = context.applicationContext
    val httpClient = HttpClient(OkHttp) {
        engine {
            config {
                proxy(Proxy.NO_PROXY)
            }
        }
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true })
        }
        install(Logging) {
            level = LogLevel.NONE
        }
    }

    val api = RealDebridApi(httpClient)
    val tokenStore: SecureTokenStore = SecureTokenStoreImpl(appContext)
    val reminderConfigStore: ReminderConfigStore = ReminderConfigStoreImpl(appContext)
    val notificationScheduler: NotificationScheduler = NotificationSchedulerImpl(appContext)
    val authRepository: AuthRepository = AuthRepositoryImpl(api, tokenStore)
    val accountRepository: AccountRepository = AccountRepositoryImpl(api, authRepository)
    val reminderRepository: ReminderRepository = ReminderRepositoryImpl(
        configStore = reminderConfigStore,
        planner = ReminderPlanner(),
        notificationScheduler = notificationScheduler
    )
    val diagnosticsRepository: DiagnosticsRepository = DiagnosticsRepositoryImpl(
        appVersionProvider = { BuildConfig.VERSION_NAME },
        osProvider = { "Android ${Build.VERSION.RELEASE}" },
        accountRepository = accountRepository,
        additionalInfoProvider = {
            mapOf(
                "notificationsEnabled" to notificationScheduler.areNotificationsEnabled().toString()
            )
        }
    )
    val fileExporter: FileExporter = FileExporterImpl(appContext)

    return AndroidAppGraph(
        authRepository = authRepository,
        accountRepository = accountRepository,
        reminderRepository = reminderRepository,
        notificationScheduler = notificationScheduler,
        exportDiagnosticsUseCase = ExportDiagnosticsUseCase(diagnosticsRepository, fileExporter),
        previewDiagnosticsUseCase = PreviewDiagnosticsUseCase(diagnosticsRepository)
    )
}
