package com.utku.debridhub.shared.platform

import kotlinx.serialization.Serializable

@Serializable
data class ExportedFile(
    val displayName: String,
    val location: String
)
