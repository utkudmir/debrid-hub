package com.utku.debridhub.shared.platform

import com.utku.debridhub.shared.domain.model.ReminderConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import platform.Foundation.NSUserDefaults

class ReminderConfigStoreImpl(
    private val defaults: NSUserDefaults = NSUserDefaults.standardUserDefaults,
    private val json: Json = Json { ignoreUnknownKeys = true }
) : ReminderConfigStore {
    override suspend fun read(): ReminderConfig = withContext(Dispatchers.Default) {
        defaults.stringForKey(KEY_CONFIG)
            ?.let { runCatching { json.decodeFromString<ReminderConfig>(it) }.getOrNull() }
            ?: ReminderConfig()
    }

    override suspend fun write(config: ReminderConfig) = withContext(Dispatchers.Default) {
        defaults.setObject(json.encodeToString(config), forKey = KEY_CONFIG)
    }

    private companion object {
        const val KEY_CONFIG = "reminder_config"
    }
}
