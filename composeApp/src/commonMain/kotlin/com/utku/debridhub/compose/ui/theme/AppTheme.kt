package com.utku.debridhub.compose.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * Defines the color palette for both light and dark themes.  Keeping
 * customization to a minimum ensures accessibility and predictable contrast.
 */
private val LightColors = lightColorScheme(
    primary = Color(0xFF2196F3),
    onPrimary = Color.White,
    secondary = Color(0xFF03A9F4),
    onSecondary = Color.White,
    background = Color(0xFFF5F5F5),
    onBackground = Color(0xFF212121),
    surface = Color.White,
    onSurface = Color(0xFF212121),
    error = Color(0xFFB00020),
    onError = Color.White
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF90CAF9),
    onPrimary = Color(0xFF212121),
    secondary = Color(0xFF81D4FA),
    onSecondary = Color(0xFF212121),
    background = Color(0xFF303030),
    onBackground = Color(0xFFF5F5F5),
    surface = Color(0xFF424242),
    onSurface = Color(0xFFF5F5F5),
    error = Color(0xFFCF6679),
    onError = Color(0xFF212121)
)

/**
 * A simple wrapper around [MaterialTheme] that provides light and dark
 * color schemes.  The theme could be extended to support dynamic colors or
 * user preferences by exposing a parameter.
 */
@Composable
fun AppTheme(
    useDarkTheme: Boolean = false,
    content: @Composable () -> Unit
) {
    val colors = if (useDarkTheme) DarkColors else LightColors
    MaterialTheme(
        colorScheme = colors,
        typography = MaterialTheme.typography,
        content = content
    )
}