package com.utku.debridhub.shared.domain.model

import kotlinx.serialization.Serializable

@Serializable
data class DiagnosticsBundle(
    val appVersion: String,
    val os: String,
    val lastSync: String?,
    val accountState: String?,
    val additionalInfo: Map<String, String>
)
