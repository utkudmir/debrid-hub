package com.utku.debridhub.shared.domain.repository

import com.utku.debridhub.shared.domain.model.AuthPollResult
import com.utku.debridhub.shared.domain.model.DeviceAuthSession
import com.utku.debridhub.shared.domain.model.StoredAuthState

interface AuthRepository {
    suspend fun startAuthorization(): DeviceAuthSession
    suspend fun pollAuthorization(): AuthPollResult
    suspend fun getStoredAuthState(): StoredAuthState?
    suspend fun ensureValidAccessToken(): String?
    suspend fun isAuthenticated(): Boolean
    suspend fun disconnect()
}
