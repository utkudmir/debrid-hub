package com.utku.debridhub.shared.platform

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.utku.debridhub.shared.domain.model.StoredAuthState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class SecureTokenStoreImpl(
    context: Context,
    private val json: Json = Json { ignoreUnknownKeys = true }
) : SecureTokenStore {
    private val prefs by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "debridhub_secure_prefs",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    override suspend fun read(): StoredAuthState? = withContext(Dispatchers.IO) {
        prefs.getString(KEY_AUTH_STATE, null)
            ?.let { raw -> runCatching { json.decodeFromString<StoredAuthState>(raw) }.getOrNull() }
    }

    override suspend fun write(state: StoredAuthState) = withContext(Dispatchers.IO) {
        prefs.edit().putString(KEY_AUTH_STATE, json.encodeToString(state)).apply()
    }

    override suspend fun clear() = withContext(Dispatchers.IO) {
        prefs.edit().clear().apply()
    }

    private companion object {
        const val KEY_AUTH_STATE = "auth_state"
    }
}
