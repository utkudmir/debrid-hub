package com.utku.debridhub.shared.core

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
                "Secure connection to Real-Debrid failed. " +
                    "Your network appears to be intercepting or downgrading HTTPS traffic " +
                    "to api.real-debrid.com. Disable captive portals, VPNs, secure web " +
                    "gateways, or TLS inspection, or try a different network."
            }
            networkReachabilitySignals.any(normalized::contains) -> {
                "Couldn't reach Real-Debrid. Check your internet connection or try a different network."
            }
            trimmed.isNotEmpty() -> trimmed
            else -> fallback
        }
    }
}
