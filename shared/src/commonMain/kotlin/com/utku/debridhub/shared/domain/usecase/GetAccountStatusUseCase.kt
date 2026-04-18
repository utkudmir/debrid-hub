package com.utku.debridhub.shared.domain.usecase

import com.utku.debridhub.shared.domain.repository.AccountRepository

/**
 * Fetches the latest account status from the [AccountRepository].  This use
 * case should be invoked when the UI needs to display up‑to‑date
 * information about the user’s subscription.  Caching and token refresh
 * logic is handled by the repository implementation.
 */
class GetAccountStatusUseCase(private val accountRepository: AccountRepository) {
    suspend operator fun invoke() = accountRepository.refreshAccountStatus()
}