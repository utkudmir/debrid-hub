package com.utku.debridhub.compose.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.utku.debridhub.compose.ui.components.PrimaryButton

/**
 * Simple onboarding screen that explains what the app does and asks the user
 * to connect their Real‑Debrid account.  It also offers the option to
 * proactively request notification permission so that the app can schedule
 * reminders when the subscription is nearing expiration.  The actual
 * permission request must be implemented by the platform layer and passed
 * through via the provided callback.
 */
@Composable
fun OnboardingScreen(
    onConnect: () -> Unit,
    onRequestNotificationPermission: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(24.dp)
    ) {
        Text(
            text = "Welcome to DebridHub",
            style = MaterialTheme.typography.headlineSmall
        )
        Text(
            text = "DebridHub helps you keep track of your Real‑Debrid subscription and reminds you before it expires. Your credentials stay on your device and are never sent to our servers.",
            style = MaterialTheme.typography.bodyMedium
        )
        Spacer(modifier = Modifier.height(16.dp))
        PrimaryButton(onClick = onConnect) {
            Text("Connect Real‑Debrid")
        }
        PrimaryButton(onClick = onRequestNotificationPermission) {
            Text("Enable Notifications")
        }
    }
}