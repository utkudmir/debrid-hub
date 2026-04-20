package app.debridhub.shared.localization

internal sealed interface LocalizationEntry {
    data class Text(val template: String) : LocalizationEntry

    data class Plural(
        val one: String,
        val other: String
    ) : LocalizationEntry
}

object AppLocalization {
    private var overrideLanguageTags: List<String>? = null

    fun text(key: String, vararg args: String): String =
        resolve(
            key = key,
            args = args.toList(),
            count = null,
            languageTags = overrideLanguageTags ?: platformLanguageTags()
        )

    fun textForLanguageTags(
        languageTags: List<String>,
        key: String,
        vararg args: String
    ): String = resolve(
        key = key,
        args = args.toList(),
        count = null,
        languageTags = languageTags
    )

    fun plural(
        key: String,
        count: Int,
        vararg args: String
    ): String {
        val resolvedArgs = if (args.isEmpty()) listOf(count.toString()) else args.toList()
        return resolve(
            key = key,
            args = resolvedArgs,
            count = count,
            languageTags = overrideLanguageTags ?: platformLanguageTags()
        )
    }

    fun pluralForLanguageTags(
        languageTags: List<String>,
        key: String,
        count: Int,
        vararg args: String
    ): String {
        val resolvedArgs = if (args.isEmpty()) listOf(count.toString()) else args.toList()
        return resolve(
            key = key,
            args = resolvedArgs,
            count = count,
            languageTags = languageTags
        )
    }

    fun setOverrideLanguageTagsForTesting(languageTags: List<String>?) {
        overrideLanguageTags = languageTags
    }

    internal fun resolve(
        key: String,
        args: List<String>,
        count: Int?,
        languageTags: List<String>
    ): String {
        val localeChain = buildLocaleFallbackChain(languageTags)
        val entry = localeChain.firstNotNullOfOrNull { locale ->
            GeneratedLocalizationCatalog.entries[locale]?.get(key)
        } ?: error("Missing localization key: $key")

        val template = when (entry) {
            is LocalizationEntry.Text -> entry.template
            is LocalizationEntry.Plural -> selectPluralForm(entry, localeChain.first(), count)
        }

        return applyArguments(template, args)
    }

    private fun buildLocaleFallbackChain(languageTags: List<String>): List<String> {
        val resolved = linkedSetOf<String>()
        for (languageTag in languageTags) {
            val normalized = languageTag.trim()
            if (normalized.isEmpty()) continue
            resolved += normalized
            val baseLanguage = normalized.substringBefore('-')
            if (baseLanguage.isNotEmpty()) {
                resolved += baseLanguage
            }
        }
        resolved += GeneratedLocalizationCatalog.baseLocale
        return resolved.toList()
    }

    private fun selectPluralForm(
        entry: LocalizationEntry.Plural,
        localeTag: String,
        count: Int?
    ): String {
        val resolvedCount = count ?: 0
        val language = localeTag.substringBefore('-').lowercase()
        val useOne = when (language) {
            "fr" -> resolvedCount == 0 || resolvedCount == 1
            else -> resolvedCount == 1
        }
        return if (useOne) entry.one else entry.other
    }

    private fun applyArguments(
        template: String,
        args: List<String>
    ): String {
        var resolved = template
        args.forEachIndexed { index, value ->
            resolved = resolved.replace("%{${index + 1}}", value)
        }
        return resolved
    }
}

internal expect fun platformLanguageTags(): List<String>
