package com.utku.debridhub.shared.domain.usecase

import com.utku.debridhub.shared.domain.repository.DiagnosticsRepository
import com.utku.debridhub.shared.platform.ExportedFile
import com.utku.debridhub.shared.platform.FileExporter
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class ExportDiagnosticsUseCase(
    private val diagnosticsRepository: DiagnosticsRepository,
    private val fileExporter: FileExporter,
    private val json: Json = Json { prettyPrint = true }
) {
    suspend operator fun invoke(): Result<ExportedFile> = runCatching {
        val payload = json.encodeToString(diagnosticsRepository.collectDiagnostics())
        fileExporter.exportTextFile("diagnostics.json", payload)
    }
}
