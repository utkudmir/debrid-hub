package com.utku.debridhub.shared.data.repository

import com.utku.debridhub.shared.domain.repository.AccountRepository
import com.utku.debridhub.shared.domain.repository.DiagnosticsRepository
import com.utku.debridhub.shared.domain.model.DiagnosticsBundle

class DiagnosticsRepositoryImpl(
    private val appVersionProvider: () -> String,
    private val osProvider: () -> String,
    private val accountRepository: AccountRepository,
    private val additionalInfoProvider: suspend () -> Map<String, String> = { emptyMap() }
) : DiagnosticsRepository {
    override suspend fun collectDiagnostics(): DiagnosticsBundle {
        val accountStatus = accountRepository.getCachedAccountStatus()
        return DiagnosticsBundle(
            appVersion = appVersionProvider(),
            os = osProvider(),
            lastSync = accountStatus?.lastCheckedAt?.toString(),
            accountState = accountStatus?.expiryState?.name,
            additionalInfo = sanitizeAdditionalInfo(additionalInfoProvider())
        )
    }

    private fun sanitizeAdditionalInfo(raw: Map<String, String>): Map<String, String> {
        return raw.filterKeys { key ->
            val normalized = key.lowercase()
            sensitiveKeySignals.none(normalized::contains)
        }.filterValues { value ->
            sensitiveValuePatterns.none { pattern -> pattern.containsMatchIn(value) }
        }
    }

    private companion object {
        val sensitiveKeySignals = listOf(
            "token",
            "secret",
            "password",
            "authorization",
            "bearer",
            "cookie",
            "email",
            "username",
            "user_name",
            "login"
        )

        val sensitiveValuePatterns = listOf(
            Regex("""(?i)^bearer\s+.+$"""),
            Regex("""(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}""")
        )
    }
}
