package app.debridhub.android

import app.debridhub.shared.localization.AppLocalization
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test

class LocalizationSmokeTest {
    @After
    fun tearDown() {
        AppLocalization.setOverrideLanguageTagsForTesting(null)
    }

    @Test
    fun resolvesSpanishMessageFromAndroidLayer() {
        AppLocalization.setOverrideLanguageTagsForTesting(listOf("es"))

        assertEquals(
            "Notificaciones activadas.",
            localizedTextForCurrentLocale("messages.notifications_enabled")
        )
    }
}
