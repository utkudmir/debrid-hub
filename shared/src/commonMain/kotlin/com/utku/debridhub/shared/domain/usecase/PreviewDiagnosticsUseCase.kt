package com.utku.debridhub.shared.domain.usecase

import com.utku.debridhub.shared.domain.repository.DiagnosticsRepository
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class PreviewDiagnosticsUseCase(
    private val diagnosticsRepository: DiagnosticsRepository,
    private val json: Json = Json { prettyPrint = true }
) {
    suspend operator fun invoke(): Result<String> = runCatching {
        json.encodeToString(diagnosticsRepository.collectDiagnostics())
    }
}
