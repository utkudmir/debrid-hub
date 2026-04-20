package app.debridhub.shared.localization

import android.os.Build
import java.util.Locale

internal actual fun platformLanguageTags(): List<String> {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        val languageTags = Locale.getDefault().toLanguageTag()
        return if (languageTags.isBlank()) listOf("en") else listOf(languageTags)
    }

    val locale = Locale.getDefault()
    val languageTag = buildString {
        append(locale.language)
        if (locale.country.isNotBlank()) {
            append('-')
            append(locale.country)
        }
    }
    return if (languageTag.isBlank()) listOf("en") else listOf(languageTag)
}
