package com.utku.debridhub.shared.data.repository

import com.utku.debridhub.shared.domain.model.AccountStatus
import com.utku.debridhub.shared.domain.model.ExpiryState
import com.utku.debridhub.shared.domain.repository.AccountRepository
import com.utku.debridhub.shared.domain.usecase.PreviewDiagnosticsUseCase
import kotlinx.coroutines.runBlocking
import kotlinx.datetime.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DiagnosticsRepositoryImplTest {
    private val cachedStatus = AccountStatus(
        username = "sensitive-user",
        expiration = Instant.parse("2026-04-20T00:00:00Z"),
        remainingDays = 8,
        premiumSeconds = 691200,
        isPremium = true,
        lastCheckedAt = Instant.parse("2026-04-12T00:00:00Z"),
        expiryState = ExpiryState.ACTIVE
    )

    @Test
    fun `collect diagnostics strips sensitive additional info entries`() = runBlocking {
        val repository = DiagnosticsRepositoryImpl(
            appVersionProvider = { "1.0.0" },
            osProvider = { "iOS 18" },
            accountRepository = FakeAccountRepository(cachedStatus),
            additionalInfoProvider = {
                mapOf(
                    "notificationsEnabled" to "true",
                    "refreshToken" to "secret-value",
                    "supportEmail" to "user@example.com",
                    "authorizationHeader" to "Bearer abc123",
                    "buildFlavor" to "debug"
                )
            }
        )

        val diagnostics = repository.collectDiagnostics()

        assertEquals("1.0.0", diagnostics.appVersion)
        assertEquals("ACTIVE", diagnostics.accountState)
        assertEquals(
            mapOf(
                "notificationsEnabled" to "true",
                "buildFlavor" to "debug"
            ),
            diagnostics.additionalInfo
        )
    }

    @Test
    fun `preview diagnostics json excludes tokens username and email`() = runBlocking {
        val repository = DiagnosticsRepositoryImpl(
            appVersionProvider = { "1.0.0" },
            osProvider = { "Android 16" },
            accountRepository = FakeAccountRepository(cachedStatus),
            additionalInfoProvider = {
                mapOf(
                    "notificationsEnabled" to "false",
                    "client_secret" to "top-secret",
                    "sessionEmail" to "user@example.com"
                )
            }
        )
        val useCase = PreviewDiagnosticsUseCase(repository)

        val preview = useCase().getOrThrow()

        assertTrue(preview.contains("notificationsEnabled"))
        assertFalse(preview.contains("sensitive-user"))
        assertFalse(preview.contains("user@example.com"))
        assertFalse(preview.contains("top-secret"))
        assertFalse(preview.contains("client_secret"))
    }
}

private class FakeAccountRepository(
    private val cached: AccountStatus?
) : AccountRepository {
    override suspend fun refreshAccountStatus(): Result<AccountStatus> =
        cached?.let { Result.success(it) } ?: Result.failure(IllegalStateException("No status"))

    override suspend fun getCachedAccountStatus(): AccountStatus? = cached
}
