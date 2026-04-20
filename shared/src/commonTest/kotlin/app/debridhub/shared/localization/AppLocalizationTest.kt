package app.debridhub.shared.localization

import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals

class AppLocalizationTest {
    @AfterTest
    fun tearDown() {
        AppLocalization.setOverrideLanguageTagsForTesting(null)
    }

    @Test
    fun fallsBackToBaseLocaleForUnsupportedLanguage() {
        AppLocalization.setOverrideLanguageTagsForTesting(listOf("it"))

        assertEquals("DebridHub", AppLocalization.text("common.app_name"))
    }

    @Test
    fun resolvesPluralForTurkishLocale() {
        AppLocalization.setOverrideLanguageTagsForTesting(listOf("tr"))

        assertEquals(
            "Real-Debrid aboneliğin 3 gün içinde sona erecek",
            AppLocalization.plural("reminders.notification.expires_in", 3, "3")
        )
    }

    @Test
    fun resolvesLocalizedPlainTextForGermanLocale() {
        AppLocalization.setOverrideLanguageTagsForTesting(listOf("de-DE"))

        assertEquals("Vertrauenszentrum", AppLocalization.text("common.trust_center"))
    }
}
