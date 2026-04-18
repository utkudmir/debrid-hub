package com.utku.debridhub.shared.domain.repository

import com.utku.debridhub.shared.domain.model.DiagnosticsBundle

/**
 * Collects diagnostic information about the app state and environment. The
 * repository should not send this information anywhere; instead it returns
 * it to the caller, which can then be exported via [FileExporter].
 */
interface DiagnosticsRepository {
    /**
     * Gather diagnostics information. Implementations may gather system
     * information, last sync times and other non‑sensitive details.
     */
    suspend fun collectDiagnostics(): DiagnosticsBundle
}