package com.utku.debridhub.shared.core

import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals

class RealDebridErrorMessagesTest {
    @Test
    fun `secure connection issues map to actionable guidance`() {
        val message = RealDebridErrorMessages.presentableMessage(
            details = "javax.net.ssl.SSLException: Unrecognized SSL message, plaintext connection?",
            fallback = "fallback"
        )

        assertContains(message, "Secure connection to Real-Debrid failed.")
        assertContains(message, "api.real-debrid.com")
    }

    @Test
    fun `network reachability issues map to connectivity guidance`() {
        val message = RealDebridErrorMessages.presentableMessage(
            details = "Unable to resolve host api.real-debrid.com",
            fallback = "fallback"
        )

        assertEquals(
            "Couldn't reach Real-Debrid. Check your internet connection or try a different network.",
            message
        )
    }

    @Test
    fun `unknown issues fall back to raw message`() {
        val message = RealDebridErrorMessages.presentableMessage(
            details = "authorization_pending",
            fallback = "fallback"
        )

        assertEquals("authorization_pending", message)
    }
}
