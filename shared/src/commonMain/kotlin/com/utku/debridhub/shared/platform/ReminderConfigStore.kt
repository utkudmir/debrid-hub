package com.utku.debridhub.shared.platform

import com.utku.debridhub.shared.domain.model.ReminderConfig

interface ReminderConfigStore {
    suspend fun read(): ReminderConfig
    suspend fun write(config: ReminderConfig)
}
