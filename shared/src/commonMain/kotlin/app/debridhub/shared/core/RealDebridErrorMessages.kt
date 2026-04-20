package app.debridhub.shared.core

import app.debridhub.shared.localization.AppLocalization

object RealDebridErrorMessages {
    private val secureConnectionSignals = listOf(
        "plaintext connection",
        "wrong version number",
        "protocol version",
        "unrecognized ssl message",
        "tls",
        "ssl",
        "certificate",
        "handshake",
        "trust anchor",
        "proxy",
        "middlebox"
    )

    private val networkReachabilitySignals = listOf(
        "unable to resolve host",
        "failed to connect",
        "network is unreachable",
        "no address associated with hostname",
        "timed out",
        "timeout"
    )

    fun presentableMessage(details: String?, fallback: String): String {
        val trimmed = details?.trim().orEmpty()
        val normalized = trimmed.lowercase()

        return when {
            secureConnectionSignals.any(normalized::contains) -> {
                AppLocalization.text("errors.secure_connection_failed")
            }
            networkReachabilitySignals.any(normalized::contains) -> {
                AppLocalization.text("errors.network_unreachable")
            }
            trimmed.isNotEmpty() -> trimmed
            else -> fallback
        }
    }
}
