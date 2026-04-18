import SwiftUI
import SafariServices

struct ContentView: View {
    @ObservedObject var viewModel: IOSAppViewModel
    @State private var isTrustCenterPresented = false

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
                        if viewModel.isCheckingSession {
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

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Color.red)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("DebridHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Trust Center") {
                        isTrustCenterPresented = true
                    }
                }
            }
            .sheet(item: $viewModel.authorizationBrowserTarget) { target in
                AuthorizationSafariView(url: target.url)
            }
            .sheet(isPresented: $isTrustCenterPresented) {
                NavigationStack {
                    TrustCenterView(viewModel: viewModel)
                }
            }
        }
    }

    private var onboardingSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Keep your Real-Debrid premium from quietly expiring.")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.09, green: 0.18, blue: 0.29))
                Text("DebridHub checks your account status locally, shows time remaining, and schedules renewal reminders on this device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

            TrustCard(title: "Before you connect") {
                TrustLine("1. Tap Connect Real-Debrid to start the official device flow.")
                TrustLine("2. Copy the code if you want, then approve the device in the Real-Debrid browser page.")
                TrustLine("3. If the browser sheet closes early, use Open Authorization Page below to reopen it.")
                TrustLine("4. Return here while DebridHub polls locally for completion.")
                TrustLine("Open Trust Center first if you want to inspect privacy, security, diagnostics, and compliance details.")
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(title: "Private by default", detail: "No backend, no analytics, no token sharing.")
                FeatureRow(title: "Native reminders", detail: "Local iOS notifications before expiry.")
                FeatureRow(title: "Device flow login", detail: "Authorize safely in the Real-Debrid browser flow.")
            }
            .padding(20)
            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Button("Connect Real-Debrid") {
                    viewModel.startAuthorization()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if viewModel.notificationPermissionState == .notDetermined || viewModel.notificationPermissionState == .unknown {
                    Button(viewModel.isRequestingNotifications ? "Enabling Notifications..." : "Enable Notifications") {
                        viewModel.requestNotifications()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else if viewModel.notificationPermissionState == .denied {
                    Button("Open Notification Settings") {
                        viewModel.openAppSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Group {
                    if viewModel.notificationPermissionState == .granted {
                        Text("Notifications are already enabled on this device.")
                    } else if viewModel.notificationPermissionState == .denied {
                        Text("Notifications are disabled for DebridHub. Re-enable them in Settings if you want reminder alerts.")
                    } else {
                        Text("You can grant notification permission now or later. Reminders start once your account is connected.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let code = viewModel.userCode {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Finish authorization")
                        .font(.headline)
                    Text("Code")
                        .font(.subheadline.weight(.semibold))
                    Text(code)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                    Button("Copy Code") {
                        UIPasteboard.general.string = code
                    }
                    .buttonStyle(.bordered)
                    if let verificationURL = viewModel.verificationURL {
                        Text(verificationURL)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let directVerificationURL = viewModel.directVerificationURL {
                        Text(directVerificationURL)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Waiting for Real-Debrid approval. After you approve the device, come back here and DebridHub will finish the login automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Open Authorization Page") {
                        if let directVerificationURL = viewModel.directVerificationURL,
                           let url = URL(string: directVerificationURL) {
                            viewModel.authorizationBrowserTarget = AuthorizationBrowserTarget(url: url)
                        } else if let verificationURL = viewModel.verificationURL,
                                  let url = URL(string: verificationURL) {
                            viewModel.authorizationBrowserTarget = AuthorizationBrowserTarget(url: url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancel Authorization") {
                        viewModel.cancelAuthorization()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            if viewModel.errorMessage != nil && viewModel.userCode == nil {
                Button("Start Again") {
                    viewModel.startAuthorization()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var accountSection: some View {
        TrustCard(title: "Account Status") {
            TrustLine("Username: \(viewModel.accountStatus?.username ?? "Unknown")")
            TrustLine("State: \(viewModel.accountStatus?.expiryState.name ?? "UNKNOWN")")
            TrustLine("Days remaining: \(viewModel.accountStatus?.remainingDays?.description ?? "Unknown")")
            TrustLine("Expires: \(viewModel.accountStatus?.expiration?.description() ?? "Unknown")")
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(viewModel.isRefreshing ? "Refreshing..." : "Refresh Status") {
                Task { await viewModel.refreshAccount() }
            }
            .buttonStyle(.borderedProminent)
            if viewModel.notificationPermissionState == .notDetermined || viewModel.notificationPermissionState == .unknown {
                Button(viewModel.isRequestingNotifications ? "Enable Notifications..." : "Enable Notifications") {
                    viewModel.requestNotifications()
                }
                .buttonStyle(.bordered)
            } else if viewModel.notificationPermissionState == .denied {
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
            } else if viewModel.notificationPermissionState == .denied {
                TrustLine("Reminders are planned, but iOS notifications are currently disabled for DebridHub. Re-enable them in Settings if you want these alerts to fire.")
                if viewModel.scheduledReminders.isEmpty {
                    TrustLine("No future reminders are planned right now. This can happen when the expiry date is very close, already passed, or all reminder windows are already behind you.")
                } else {
                    TrustLine("Planned reminder times:")
                    ForEach(Array(viewModel.scheduledReminders.enumerated()), id: \.offset) { _, reminder in
                        TrustLine("\(String(describing: reminder.fireAt)): \(reminder.message)")
                    }
                }
            } else if viewModel.scheduledReminders.isEmpty {
                TrustLine("No future reminders are planned right now. This can happen when the expiry date is very close, already passed, or all reminder windows are already behind you.")
            } else {
                TrustLine("DebridHub will schedule these local notifications on this device:")
                ForEach(Array(viewModel.scheduledReminders.enumerated()), id: \.offset) { _, reminder in
                    TrustLine("\(String(describing: reminder.fireAt)): \(reminder.message)")
                }
            }
        }
    }
}

private struct TrustCenterView: View {
    @ObservedObject var viewModel: IOSAppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("See exactly how DebridHub handles auth, storage, diagnostics, and feature boundaries.")
                    .font(.title2.bold())
                    .foregroundStyle(Color(red: 0.09, green: 0.18, blue: 0.29))

                Text("This Trust Center is native app UI based on the current implementation, not a webview or marketing page.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                TrustCard(title: "Privacy") {
                    TrustLine("DebridHub has no backend. The app talks directly to Real-Debrid from your device.")
                    TrustLine("There is no analytics SDK, tracking layer, crash-reporting service, or remote account sync in the current product.")
                    TrustLine("Reminder notifications are local to this device.")
                    TrustLine("Diagnostics export is manual and local until you explicitly choose to share the exported file yourself.")
                }

                TrustCard(title: "Security") {
                    TrustLine("Authentication uses Real-Debrid's official OAuth2 device flow instead of password collection.")
                    TrustLine("Android stores auth state with EncryptedSharedPreferences.")
                    TrustLine("iOS stores auth state in Keychain and migrates legacy NSUserDefaults auth state on first read.")
                    TrustLine("Disconnect clears stored auth state and cancels reminders.")
                }

                TrustCard(title: "Diagnostics") {
                    TrustLine("Diagnostics export currently includes app version, OS version, last sync timestamp, account expiry state, and limited non-sensitive runtime flags.")
                    TrustLine("Diagnostics export excludes access tokens, refresh tokens, client secrets, username, email, and account history.")

                    HStack {
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
                    TrustLine("Current scope is intentionally narrow: account auth, account-status reads, local reminder scheduling, and local diagnostics export.")
                    TrustLine("The app does not currently implement unrestrict, downloads, torrent management, streaming, generated-link sharing, or multi-user account management.")
                    TrustLine("DebridHub uses official Real-Debrid API endpoints and the documented device-auth flow, but users still need to follow Real-Debrid's own Terms and account rules.")
                }
            }
            .padding(24)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.91, green: 0.95, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Trust Center")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task {
            viewModel.loadDiagnosticsPreview()
        }
    }
}

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

private struct FeatureRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(red: 0.09, green: 0.18, blue: 0.29))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
