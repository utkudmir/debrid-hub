package app.debridhub.android

import android.content.res.Configuration
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import app.debridhub.shared.localization.AppLocalization
import kotlinx.datetime.Instant
import java.text.DateFormat
import java.text.NumberFormat
import java.util.Date
import java.util.Locale

@Composable
internal fun localizedText(
    key: String,
    vararg args: String
): String {
    val languageTags = LocalConfiguration.current.toLanguageTags()
    return AppLocalization.textForLanguageTags(languageTags, key, *args)
}

@Composable
internal fun localizedPlural(
    key: String,
    count: Int,
    vararg args: String
): String {
    val languageTags = LocalConfiguration.current.toLanguageTags()
    return AppLocalization.pluralForLanguageTags(languageTags, key, count, *args)
}

internal fun localizedTextForCurrentLocale(
    key: String,
    vararg args: String
): String = AppLocalization.text(key, *args)

internal fun formatInstantForLocale(instant: Instant): String {
    val formatter = DateFormat.getDateTimeInstance(
        DateFormat.MEDIUM,
        DateFormat.SHORT,
        Locale.getDefault()
    )
    return formatter.format(Date(instant.toEpochMilliseconds()))
}

internal fun formatIntegerForLocale(value: Int): String =
    NumberFormat.getIntegerInstance(Locale.getDefault()).format(value)

private fun Configuration.toLanguageTags(): List<String> {
    val tags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        locales.toLanguageTags()
    } else {
        @Suppress("DEPRECATION")
        locale.toLanguageTag()
    }

    return tags.split(',').map(String::trim).filter(String::isNotEmpty).ifEmpty { listOf("en") }
}
