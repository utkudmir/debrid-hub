package app.debridhub.shared.domain.repository

import app.debridhub.shared.domain.model.AccountStatus

/**
 * Provides current account status information for the authenticated user.
 * This repository hides the details of API requests and token management.
 */
interface AccountRepository {
    /**
     * Refresh the account information from the network. This should be
     * invoked when the user explicitly requests an update or when the app
     * launches. Implementations should perform token refresh internally if
     * necessary.
     */
    suspend fun refreshAccountStatus(): Result<AccountStatus>

    /**
     * Return the cached account status if available. If no cached value is
     * present this should return null. Reading the cache should not perform
     * any network calls.
     */
    suspend fun getCachedAccountStatus(): AccountStatus?
}
