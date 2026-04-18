package com.utku.debridhub.android

import android.content.ClipData
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.utku.debridhub.shared.domain.model.AccountStatus
import com.utku.debridhub.shared.domain.model.ReminderConfig
import com.utku.debridhub.shared.domain.model.ScheduledReminder
import kotlinx.coroutines.launch
import kotlinx.datetime.Instant
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DebridHubApp(
    viewModel: DebridHubViewModel,
    onOpenUrl: (String) -> Unit,
    onShareDiagnostics: (String, String) -> Unit,
    onRequestNotificationPermission: () -> Unit,
    onOpenNotificationSettings: () -> Unit
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    var isTrustCenterOpen by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(viewModel) {
        viewModel.events.collect { event ->
            when (event) {
                is DebridHubEvent.OpenUrl -> onOpenUrl(event.url)
                is DebridHubEvent.ShareDiagnostics -> onShareDiagnostics(event.displayName, event.location)
                DebridHubEvent.RequestNotificationPermission -> onRequestNotificationPermission()
                is DebridHubEvent.Message -> snackbarHostState.showSnackbar(event.value)
            }
        }
    }

    LaunchedEffect(isTrustCenterOpen) {
        if (isTrustCenterOpen) {
            viewModel.loadDiagnosticsPreview()
        }
    }

    MaterialTheme {
        Scaffold(
            snackbarHost = { SnackbarHost(hostState = snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text(if (isTrustCenterOpen) "Trust Center" else "DebridHub") },
                    navigationIcon = {
                        if (isTrustCenterOpen) {
                            TextButton(onClick = { isTrustCenterOpen = false }) {
                                Text("Back")
                            }
                        }
                    },
                    actions = {
                        if (!isTrustCenterOpen) {
                            TextButton(onClick = { isTrustCenterOpen = true }) {
                                Text("Trust Center")
                            }
                        }
                    }
                )
            }
        ) { padding ->
            when {
                isTrustCenterOpen -> {
                    TrustCenterScreen(
                        modifier = Modifier.padding(padding),
                        uiState = uiState,
                        onRefreshPreview = viewModel::loadDiagnosticsPreview,
                        onExportDiagnostics = viewModel::exportDiagnostics
                    )
                }
                uiState.checkingSession -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                }
                uiState.isAuthenticated -> {
                    HomeScreen(
                        modifier = Modifier.padding(padding),
                        uiState = uiState,
                        onRefresh = viewModel::refreshAccountStatus,
                        onDisconnect = viewModel::disconnect,
                        onRequestNotifications = viewModel::requestNotificationPermission,
                        onOpenNotificationSettings = onOpenNotificationSettings,
                        onReminderEnabledChanged = viewModel::setReminderEnabled,
                        onReminderDayToggled = viewModel::toggleReminderDay,
                        onNotifyOnExpiryChanged = viewModel::setNotifyOnExpiry,
                        onNotifyAfterExpiryChanged = viewModel::setNotifyAfterExpiry
                    )
                }
                else -> {
                    OnboardingScreen(
                        modifier = Modifier.padding(padding),
                        uiState = uiState,
                        onConnect = viewModel::startAuthorization,
                        onCancel = viewModel::cancelAuthorization,
                        onOpenAuthorizationPage = onOpenUrl,
                        onRequestNotifications = viewModel::requestNotificationPermission,
                        onOpenNotificationSettings = onOpenNotificationSettings
                    )
                }
            }
        }
    }
}

@Composable
private fun OnboardingScreen(
    modifier: Modifier,
    uiState: DebridHubUiState,
    onConnect: () -> Unit,
    onCancel: () -> Unit,
    onOpenAuthorizationPage: (String) -> Unit,
    onRequestNotifications: () -> Unit,
    onOpenNotificationSettings: () -> Unit
) {
    val clipboard = LocalClipboard.current
    val coroutineScope = rememberCoroutineScope()

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            "Track your Real-Debrid subscription and renew before it lapses.",
            style = MaterialTheme.typography.headlineSmall
        )
        Text("DebridHub talks directly to the official Real-Debrid API. Tokens stay on device and no backend is involved.")

        SectionCard(title = "Before you connect") {
            Text("1. Tap Connect Real-Debrid to request a device code.")
            Text("2. Copy the code if you want, then approve the device on Real-Debrid.")
            Text("3. If your browser handoff is interrupted, use Open Page below.")
            Text("4. Return here while DebridHub polls for completion.")
            Text("You can open Trust Center first if you want to inspect privacy, security, diagnostics, and compliance details.")
        }

        uiState.errorMessage?.let {
            Text(it, color = MaterialTheme.colorScheme.error)
        }

        val session = uiState.onboarding.session
        if (session != null) {
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Finish authorization", fontWeight = FontWeight.SemiBold)
                    Text("Enter this code on Real-Debrid.")
                    SelectionContainer {
                        Text(session.userCode, style = MaterialTheme.typography.headlineSmall)
                    }
                    Text("Verification URL: ${session.verificationUrl}")
                    session.directVerificationUrl?.let { directUrl ->
                        Text("Direct verification URL: $directUrl")
                    }
                    Text("Polling every ${session.pollIntervalSeconds}s until ${formatInstant(session.expiresAt)}")
                    Text("Waiting for Real-Debrid approval. After you approve the device, come back here and DebridHub will finish the login automatically.")
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                        OutlinedButton(
                            onClick = {
                                coroutineScope.launch {
                                    clipboard.setClipEntry(
                                        ClipEntry(ClipData.newPlainText("DebridHub Auth Code", session.userCode))
                                    )
                                }
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Copy Code")
                        }
                        OutlinedButton(
                            onClick = { onOpenAuthorizationPage(session.directVerificationUrl ?: session.verificationUrl) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Open Page")
                        }
                    }
                    OutlinedButton(onClick = onCancel, modifier = Modifier.fillMaxWidth()) {
                        Text("Cancel Authorization")
                    }
                }
            }
        }

        if (uiState.errorMessage != null && session == null) {
            OutlinedButton(
                onClick = onConnect,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Start Again")
            }
        }

        Button(
            onClick = onConnect,
            enabled = !uiState.onboarding.isStarting && !uiState.onboarding.isPolling,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(if (uiState.onboarding.isStarting) "Starting..." else "Connect Real-Debrid")
        }

        when (uiState.notificationPermissionState) {
            NotificationPermissionUiState.Granted -> {
                Text("Notifications are already enabled on this device.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            NotificationPermissionUiState.Disabled,
            NotificationPermissionUiState.Unknown -> {
                OutlinedButton(
                    onClick = onRequestNotifications,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Enable Notifications")
                }
                if (uiState.notificationPermissionState == NotificationPermissionUiState.Disabled) {
                    OutlinedButton(
                        onClick = onOpenNotificationSettings,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Open Notification Settings")
                    }
                    Text(
                        "Notifications are currently disabled for DebridHub. You can try the permission prompt again or re-enable alerts from system settings.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    Text(
                        "You can enable notifications now or later. Reminder alerts start once your account is connected.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun HomeScreen(
    modifier: Modifier,
    uiState: DebridHubUiState,
    onRefresh: () -> Unit,
    onDisconnect: () -> Unit,
    onRequestNotifications: () -> Unit,
    onOpenNotificationSettings: () -> Unit,
    onReminderEnabledChanged: (Boolean) -> Unit,
    onReminderDayToggled: (Int) -> Unit,
    onNotifyOnExpiryChanged: (Boolean) -> Unit,
    onNotifyAfterExpiryChanged: (Boolean) -> Unit
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        uiState.errorMessage?.let {
            Text(it, color = MaterialTheme.colorScheme.error)
        }

        AccountCard(
            accountStatus = uiState.accountStatus,
            isRefreshing = uiState.isRefreshingAccount
        )

        ReminderSettingsCard(
            config = uiState.reminderConfig,
            onReminderEnabledChanged = onReminderEnabledChanged,
            onReminderDayToggled = onReminderDayToggled,
            onNotifyOnExpiryChanged = onNotifyOnExpiryChanged,
            onNotifyAfterExpiryChanged = onNotifyAfterExpiryChanged
        )

        ReminderScheduleCard(
            accountStatus = uiState.accountStatus,
            config = uiState.reminderConfig,
            reminders = uiState.scheduledReminders,
            notificationPermissionState = uiState.notificationPermissionState
        )

        SectionCard(title = "Actions") {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                Button(onClick = onRefresh, modifier = Modifier.weight(1f)) {
                    Text("Refresh")
                }
                OutlinedButton(onClick = onRequestNotifications, modifier = Modifier.weight(1f)) {
                    Text("Notifications")
                }
            }

            if (uiState.notificationPermissionState == NotificationPermissionUiState.Disabled) {
                OutlinedButton(onClick = onOpenNotificationSettings, modifier = Modifier.fillMaxWidth()) {
                    Text("Open Notification Settings")
                }
            }

            OutlinedButton(onClick = onDisconnect, modifier = Modifier.fillMaxWidth()) {
                Text("Disconnect")
            }
        }
    }
}

@Composable
private fun TrustCenterScreen(
    modifier: Modifier,
    uiState: DebridHubUiState,
    onRefreshPreview: () -> Unit,
    onExportDiagnostics: () -> Unit
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            "See exactly how DebridHub handles auth, storage, diagnostics, and feature boundaries.",
            style = MaterialTheme.typography.headlineSmall
        )
        Text(
            "This is in-app product copy based on the current implementation, not a marketing layer or webview.",
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        SectionCard(title = "Privacy") {
            Text("DebridHub has no backend. The app talks directly to Real-Debrid from your device.")
            Text("There is no analytics SDK, tracking pixel, crash-reporting service, or remote account sync in the current app.")
            Text("Reminder notifications are local to this device and are scheduled using your locally stored account status.")
            Text("Diagnostics export is manual. Nothing is sent anywhere unless you explicitly share the exported file yourself.")
        }

        SectionCard(title = "Security") {
            Text("Authentication uses Real-Debrid's official OAuth2 device flow rather than password collection.")
            Text("Android stores auth state with EncryptedSharedPreferences.")
            Text("iOS stores auth state in Keychain and migrates legacy NSUserDefaults auth state on first read.")
            Text("Disconnect clears saved auth state and cancels reminders. DebridHub does not need a companion server to function.")
        }

        SectionCard(title = "Diagnostics") {
            Text("Diagnostics export currently includes app version, OS version, last sync timestamp, account expiry state, and limited non-sensitive runtime flags.")
            Text("Diagnostics export excludes access tokens, refresh tokens, client secrets, username, email, and full account history.")
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(
                    onClick = onRefreshPreview,
                    enabled = !uiState.isLoadingDiagnosticsPreview,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(if (uiState.isLoadingDiagnosticsPreview) "Loading..." else "Refresh Preview")
                }
                Button(
                    onClick = onExportDiagnostics,
                    enabled = !uiState.isExportingDiagnostics,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(if (uiState.isExportingDiagnostics) "Exporting..." else "Export JSON")
                }
            }

            if (uiState.isLoadingDiagnosticsPreview && uiState.diagnosticsPreview == null) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp))
            } else {
                SelectionContainer {
                    Text(
                        text = uiState.diagnosticsPreview ?: "Diagnostics preview is not available yet.",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        }

        SectionCard(title = "About & Compliance") {
            Text("Current scope is intentionally narrow: account auth, account-status reads, local reminder scheduling, and local diagnostics export.")
            Text("The app does not currently implement unrestrict, downloads, torrent management, streaming, generated-link sharing, or multi-user account management.")
            Text("DebridHub uses official Real-Debrid API endpoints and the documented device-auth flow. Users are still responsible for following Real-Debrid's own Terms and account rules.")
        }
    }
}

@Composable
private fun SectionCard(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            content()
        }
    }
}

@Composable
private fun AccountCard(accountStatus: AccountStatus?, isRefreshing: Boolean) {
    SectionCard(title = "Account Status") {
        when {
            isRefreshing && accountStatus == null -> {
                CircularProgressIndicator()
            }
            accountStatus == null -> {
                Text("No account data loaded yet.")
            }
            else -> {
                Text("Username: ${accountStatus.username ?: "Unknown"}")
                Text("Premium: ${if (accountStatus.isPremium) "Active" else "Inactive"}")
                Text("State: ${accountStatus.expiryState.name.replace('_', ' ')}")
                Text("Days remaining: ${accountStatus.remainingDays ?: "Unknown"}")
                Text("Expires: ${accountStatus.expiration?.let(::formatInstant) ?: "Unknown"}")
                Text("Last checked: ${formatInstant(accountStatus.lastCheckedAt)}")
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ReminderSettingsCard(
    config: ReminderConfig,
    onReminderEnabledChanged: (Boolean) -> Unit,
    onReminderDayToggled: (Int) -> Unit,
    onNotifyOnExpiryChanged: (Boolean) -> Unit,
    onNotifyAfterExpiryChanged: (Boolean) -> Unit
) {
    SectionCard(title = "Reminder Settings") {
        ToggleRow("Enable reminders", config.enabled, onReminderEnabledChanged)
        Text("Days before expiry")
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            listOf(7, 3, 1).forEach { day ->
                AssistChip(
                    onClick = { onReminderDayToggled(day) },
                    label = { Text("$day day${if (day == 1) "" else "s"}") }
                )
            }
        }
        Text("Selected: ${config.daysBefore.sorted().joinToString()}")
        ToggleRow("Notify on expiry day", config.notifyOnExpiry, onNotifyOnExpiryChanged)
        ToggleRow("Notify after expiry", config.notifyAfterExpiry, onNotifyAfterExpiryChanged)
    }
}

@Composable
private fun ReminderScheduleCard(
    accountStatus: AccountStatus?,
    config: ReminderConfig,
    reminders: List<ScheduledReminder>,
    notificationPermissionState: NotificationPermissionUiState
) {
    SectionCard(title = "Expected Reminder Schedule") {
        when {
            accountStatus?.expiration == null -> {
                Text("Refresh your account to preview local reminders.")
            }
            !config.enabled -> {
                Text("Reminders are currently turned off.")
            }
            notificationPermissionState == NotificationPermissionUiState.Disabled -> {
                Text("Reminders are planned, but Android notifications are currently disabled for DebridHub. Re-enable them in system settings if you want these alerts to fire.")
                if (reminders.isNotEmpty()) {
                    Text("Planned reminder times:")
                    reminders.forEach { reminder ->
                        Text("${formatInstant(reminder.fireAt)}: ${reminder.message}")
                    }
                }
            }
            reminders.isEmpty() -> {
                Text("No future reminders are planned right now. This can happen if the expiry date is very close, already passed, or your selected reminder windows are already in the past.")
            }
            else -> {
                Text("DebridHub will schedule these local notifications on this device:")
                reminders.forEach { reminder ->
                    Text("${formatInstant(reminder.fireAt)}: ${reminder.message}")
                }
            }
        }
    }
}

@Composable
private fun ToggleRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label)
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

private fun formatInstant(instant: Instant): String {
    val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault())
    return formatter.format(Date(instant.toEpochMilliseconds()))
}
