package com.utku.debridhub.shared.platform

import com.utku.debridhub.shared.domain.model.StoredAuthState

interface SecureTokenStore {
    suspend fun read(): StoredAuthState?
    suspend fun write(state: StoredAuthState)
    suspend fun clear()
}
