package app.debridhub.shared.localization

import platform.Foundation.NSUserDefaults

internal actual fun platformLanguageTags(): List<String> {
    val resolved = NSUserDefaults.standardUserDefaults
        .stringArrayForKey("AppleLanguages")
        ?.filterIsInstance<String>()
        ?.filter(String::isNotBlank)
        .orEmpty()

    return if (resolved.isEmpty()) listOf("en") else resolved
}
