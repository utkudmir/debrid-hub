package com.utku.debridhub.shared.platform

import android.content.Context
import com.utku.debridhub.shared.domain.model.ReminderConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class ReminderConfigStoreImpl(
    context: Context,
    private val json: Json = Json { ignoreUnknownKeys = true }
) : ReminderConfigStore {
    private val prefs = context.getSharedPreferences("debridhub_reminders", Context.MODE_PRIVATE)

    override suspend fun read(): ReminderConfig = withContext(Dispatchers.IO) {
        prefs.getString(KEY_CONFIG, null)
            ?.let { stored -> runCatching { json.decodeFromString<ReminderConfig>(stored) }.getOrNull() }
            ?: ReminderConfig()
    }

    override suspend fun write(config: ReminderConfig) = withContext(Dispatchers.IO) {
        prefs.edit().putString(KEY_CONFIG, json.encodeToString(config)).apply()
    }

    private companion object {
        const val KEY_CONFIG = "config_json"
    }
}
