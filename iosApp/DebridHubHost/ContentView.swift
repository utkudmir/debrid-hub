import SafariServices
import Shared
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: IOSAppViewModel
    @State private var isTrustCenterOpen = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.97, blue: 1.0),
                        Color(red: 0.91, green: 0.95, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let infoMessage = viewModel.infoMessage {
                            MessageBanner(text: infoMessage, tone: .info)
                        }

                        if let errorMessage = viewModel.errorMessage {
                            MessageBanner(text: errorMessage, tone: .error)
                        }

                        if isTrustCenterOpen {
                            trustCenterSection
                        } else if viewModel.isCheckingSession {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else if viewModel.isAuthenticated {
                            accountSection
                            reminderSettingsSection
                            reminderScheduleSection
                            actionsSection
                        } else {
                            onboardingSection
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle(isTrustCenterOpen ? "Trust Center" : "DebridHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isTrustCenterOpen {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            isTrustCenterOpen = false
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Trust Center") {
                            isTrustCenterOpen = true
                        }
                    }
                }
            }
            .sheet(item: $viewModel.authorizationBrowserTarget) { target in
                AuthorizationSafariView(url: target.url)
            }
            .onChange(of: isTrustCenterOpen) { _, isOpen in
                if isOpen {
                    viewModel.loadDiagnosticsPreview()
                }
            }
        }
    }

    private var onboardingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Track your Real-Debrid subscription and renew before it lapses.")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.09, green: 0.18, blue: 0.29))

            Text(
                "DebridHub talks directly to the official Real-Debrid API. " +
                    "Tokens stay on device and no backend is involved."
            )
                .font(.body)
                .foregroundStyle(.secondary)

            TrustCard(title: "Before you connect") {
                TrustLine("1. Tap Connect Real-Debrid to request a device code.")
                TrustLine("2. Copy the code if you want, then approve the device on Real-Debrid.")
                TrustLine("3. If your browser handoff is interrupted, use Open Authorization Page below.")
                TrustLine("4. Return here while DebridHub polls for completion.")
                TrustLine(
                    "You can open Trust Center first if you want to inspect privacy, " +
                        "security, diagnostics, and compliance details."
                )
            }

            if let code = viewModel.userCode {
                TrustCard(title: "Finish authorization") {
                    TrustLine("Enter this code on Real-Debrid.")
                    Text(code)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)

                    if let verificationURL = viewModel.verificationURL {
                        TrustLine("Verification URL: \(verificationURL)")
                    }

                    if let directVerificationURL = viewModel.directVerificationURL {
                        TrustLine("Direct verification URL: \(directVerificationURL)")
                    }

                    if let interval = viewModel.authorizationPollIntervalSeconds,
                       let expiration = currentAuthorizationExpiration {
                        TrustLine("Polling every \(interval)s until \(formatInstant(expiration))")
                    }

                    TrustLine(
                        "Waiting for Real-Debrid approval. After you approve the device, " +
                            "come back here and DebridHub will finish the login automatically."
                    )

                    HStack(spacing: 12) {
                        Button("Copy Code") {
                            UIPasteboard.general.string = code
                        }
                        .buttonStyle(.bordered)

                        Button("Open Authorization Page") {
                            openAuthorizationPage()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button("Cancel Authorization") {
                        viewModel.cancelAuthorization()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if viewModel.errorMessage != nil && viewModel.userCode == nil {
                Button("Start Again") {
                    viewModel.startAuthorization()
                }
                .buttonStyle(.bordered)
            }

            Button("Connect Real-Debrid") {
                viewModel.startAuthorization()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            switch viewModel.notificationPermissionState {
            case .granted:
                Text("Notifications are already enabled on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .denied:
                Button("Enable Notifications") {
                    viewModel.requestNotifications()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Open Notification Settings") {
                    viewModel.openAppSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text(
                    "Notifications are currently disabled for DebridHub. You can try the " +
                        "permission prompt again or re-enable alerts from system settings."
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .notDetermined, .unknown:
                Button(viewModel.isRequestingNotifications ? "Enabling Notifications..." : "Enable Notifications") {
                    viewModel.requestNotifications()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text("You can enable notifications now or later. Reminder alerts start once your account is connected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accountSection: some View {
        TrustCard(title: "Account Status") {
            if let accountStatus = viewModel.accountStatus {
                TrustLine("Username: \(accountStatus.username ?? "Unknown")")
                TrustLine("Premium: \(accountStatus.isPremium ? "Active" : "Inactive")")
                TrustLine("State: \(formatExpiryState(accountStatus.expiryState.name))")
                TrustLine("Days remaining: \(accountStatus.remainingDays?.description ?? "Unknown")")
                TrustLine("Expires: \(accountStatus.expiration.map(formatInstant) ?? "Unknown")")
                TrustLine("Last checked: \(formatInstant(accountStatus.lastCheckedAt))")
            } else if viewModel.isRefreshing {
                ProgressView()
            } else {
                TrustLine("No account data loaded yet.")
            }
        }
    }

    private var actionsSection: some View {
        TrustCard(title: "Actions") {
            HStack(spacing: 12) {
                Button(viewModel.isRefreshing ? "Refreshing..." : "Refresh Status") {
                    Task { await viewModel.refreshAccount() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRefreshing)

                Button("Notifications") {
                    viewModel.requestNotifications()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRequestingNotifications)
            }

            if viewModel.notificationPermissionState == .denied {
                Button("Open Notification Settings") {
                    viewModel.openAppSettings()
                }
                .buttonStyle(.bordered)
            }

            Button("Disconnect", role: .destructive) {
                viewModel.disconnect()
            }
            .buttonStyle(.bordered)
        }
    }

    private var reminderSettingsSection: some View {
        TrustCard(title: "Reminder Settings") {
            Toggle(
                "Enable reminders",
                isOn: Binding(
                    get: { viewModel.reminderConfig.enabled },
                    set: { viewModel.setReminderEnabled($0) }
                )
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Days before expiry")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 10) {
                    ReminderDayButton(
                        label: "7 days",
                        isSelected: viewModel.reminderConfig.sevenDayReminder,
                        action: { viewModel.toggleReminderDay(7) }
                    )
                    ReminderDayButton(
                        label: "3 days",
                        isSelected: viewModel.reminderConfig.threeDayReminder,
                        action: { viewModel.toggleReminderDay(3) }
                    )
                    ReminderDayButton(
                        label: "1 day",
                        isSelected: viewModel.reminderConfig.oneDayReminder,
                        action: { viewModel.toggleReminderDay(1) }
                    )
                }

                TrustLine("Selected: \(selectedReminderDays)")
            }

            Toggle(
                "Notify on expiry day",
                isOn: Binding(
                    get: { viewModel.reminderConfig.notifyOnExpiry },
                    set: { viewModel.setNotifyOnExpiry($0) }
                )
            )

            Toggle(
                "Notify after expiry",
                isOn: Binding(
                    get: { viewModel.reminderConfig.notifyAfterExpiry },
                    set: { viewModel.setNotifyAfterExpiry($0) }
                )
            )
        }
    }

    private var reminderScheduleSection: some View {
        TrustCard(title: "Expected Reminder Schedule") {
            if viewModel.accountStatus?.expiration == nil {
                TrustLine("Refresh your account to preview local reminders.")
            } else if !viewModel.reminderConfig.enabled {
                TrustLine("Reminders are currently turned off.")
            } else if viewModel.notificationPermissionState == .denied {
                TrustLine(
                    "Reminders are planned, but notifications are currently disabled for " +
                        "DebridHub. Re-enable them in system settings if you want these alerts to fire."
                )
                reminderListLines
            } else if viewModel.scheduledReminders.isEmpty {
                TrustLine(
                    "No future reminders are planned right now. This can happen if the " +
                        "expiry date is very close, already passed, or your selected reminder windows " +
                        "are already in the past."
                )
            } else {
                TrustLine("DebridHub will schedule these local notifications on this device:")
                reminderListLines
            }
        }
    }

    @ViewBuilder
    private var reminderListLines: some View {
        if viewModel.scheduledReminders.isEmpty {
            TrustLine(
                "No future reminders are planned right now. This can happen if the expiry " +
                    "date is very close, already passed, or your selected reminder windows are already in the past."
            )
        } else {
            TrustLine("Planned reminder times:")
            ForEach(Array(viewModel.scheduledReminders.enumerated()), id: \.offset) { _, reminder in
                TrustLine("\(formatInstant(reminder.fireAt)): \(reminder.message)")
            }
        }
    }

    private var trustCenterSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("See exactly how DebridHub handles auth, storage, diagnostics, and feature boundaries.")
                .font(.title2.bold())
                .foregroundStyle(Color(red: 0.09, green: 0.18, blue: 0.29))

            Text("This is in-app product copy based on the current implementation, not a marketing layer or webview.")
                .font(.body)
                .foregroundStyle(.secondary)

            TrustCard(title: "Privacy") {
                TrustLine("DebridHub has no backend. The app talks directly to Real-Debrid from your device.")
                TrustLine(
                    "There is no analytics SDK, tracking pixel, crash-reporting service, " +
                        "or remote account sync in the current app."
                )
                TrustLine(
                    "Reminder notifications are local to this device and are scheduled " +
                        "using your locally stored account status."
                )
                TrustLine(
                    "Diagnostics export is manual. Nothing is sent anywhere unless you " +
                        "explicitly share the exported file yourself."
                )
            }

            TrustCard(title: "Security") {
                TrustLine(
                    "Authentication uses Real-Debrid's official OAuth2 device flow rather " +
                        "than password collection."
                )
                TrustLine("Android stores auth state with EncryptedSharedPreferences.")
                TrustLine(
                    "iOS stores auth state in Keychain and migrates legacy NSUserDefaults " +
                        "auth state on first read."
                )
                TrustLine(
                    "Disconnect clears saved auth state and cancels reminders. DebridHub " +
                        "does not need a companion server to function."
                )
            }

            TrustCard(title: "Diagnostics") {
                TrustLine(
                    "Diagnostics export currently includes app version, OS version, last " +
                        "sync timestamp, account expiry state, and limited non-sensitive runtime flags."
                )
                TrustLine(
                    "Diagnostics export excludes access tokens, refresh tokens, client " +
                        "secrets, username, email, and full account history."
                )

                HStack(spacing: 12) {
                    Button(viewModel.isLoadingDiagnosticsPreview ? "Loading..." : "Refresh Preview") {
                        viewModel.loadDiagnosticsPreview()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoadingDiagnosticsPreview)

                    Button(viewModel.isExporting ? "Exporting..." : "Export JSON") {
                        viewModel.exportDiagnostics()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isExporting)
                }

                if viewModel.isLoadingDiagnosticsPreview && viewModel.diagnosticsPreview == nil {
                    ProgressView()
                } else {
                    Text(viewModel.diagnosticsPreview ?? "Diagnostics preview is not available yet.")
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            TrustCard(title: "About & Compliance") {
                TrustLine(
                    "Current scope is intentionally narrow: account auth, account-status " +
                        "reads, local reminder scheduling, and local diagnostics export."
                )
                TrustLine(
                    "The app does not currently implement unrestrict, downloads, torrent " +
                        "management, streaming, generated-link sharing, or multi-user account management."
                )
                TrustLine(
                    "DebridHub uses official Real-Debrid API endpoints and the documented " +
                        "device-auth flow. Users are still responsible for following " +
                        "Real-Debrid's own Terms and account rules."
                )
            }
        }
    }

    private var selectedReminderDays: String {
        var values: [String] = []
        if viewModel.reminderConfig.sevenDayReminder {
            values.append("7")
        }
        if viewModel.reminderConfig.threeDayReminder {
            values.append("3")
        }
        if viewModel.reminderConfig.oneDayReminder {
            values.append("1")
        }
        return values.isEmpty ? "None" : values.joined(separator: ", ")
    }

    private var currentAuthorizationExpiration: Kotlinx_datetimeInstant? {
        viewModel.authorizationExpiresAt
    }

    private func openAuthorizationPage() {
        if let directVerificationURL = viewModel.directVerificationURL,
           let url = URL(string: directVerificationURL) {
            viewModel.authorizationBrowserTarget = AuthorizationBrowserTarget(url: url)
        } else if let verificationURL = viewModel.verificationURL,
                  let url = URL(string: verificationURL) {
            viewModel.authorizationBrowserTarget = AuthorizationBrowserTarget(url: url)
        }
    }

    private func formatExpiryState(_ state: String) -> String {
        state.replacingOccurrences(of: "_", with: " ")
    }

    private func formatInstant(_ instant: Kotlinx_datetimeInstant) -> String {
        dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(instant.toEpochMilliseconds()) / 1000))
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = .current
    formatter.locale = .current
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
}()

private struct TrustCard<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(red: 0.09, green: 0.18, blue: 0.29))
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct ReminderDayButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .buttonStyle(.borderedProminent)
            .tint(isSelected ? Color(red: 0.05, green: 0.5, blue: 0.94) : Color.gray.opacity(0.35))
    }
}

private struct TrustLine: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.body)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AuthorizationSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct MessageBanner: View {
    enum Tone {
        case info
        case error
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tone == .error ? Color.red : Color(red: 0.09, green: 0.18, blue: 0.29))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var backgroundColor: Color {
        switch tone {
        case .info:
            return Color.white.opacity(0.84)
        case .error:
            return Color.red.opacity(0.08)
        }
    }
}
