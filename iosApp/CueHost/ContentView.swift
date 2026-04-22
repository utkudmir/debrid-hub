import SafariServices
import Shared
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: IOSAppViewModel
    let screenshotScene: CueScreenshotScene?
    @Environment(\.scenePhase) private var scenePhase
    @State private var isTrustCenterOpen: Bool
    @State private var hasAppliedScreenshotScene = false

    init(viewModel: IOSAppViewModel, screenshotScene: CueScreenshotScene? = nil) {
        self.viewModel = viewModel
        self.screenshotScene = screenshotScene
        _isTrustCenterOpen = State(initialValue: screenshotScene == .demoTrust)
    }

    private var isScreenshotCapture: Bool { screenshotScene != nil }

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
                            if !isScreenshotCapture {
                                MessageBanner(text: infoMessage, tone: .info)
                            }
                        }

                        if let errorMessage = viewModel.errorMessage {
                            if !isScreenshotCapture {
                                MessageBanner(text: errorMessage, tone: .error)
                            }
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
            .navigationTitle(
                isTrustCenterOpen ? localized("common.trust_center") : localized("common.app_name")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isTrustCenterOpen {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(localized("common.back")) {
                            isTrustCenterOpen = false
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(localized("common.trust_center")) {
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
            .task(id: viewModel.isCheckingSession) {
                guard !hasAppliedScreenshotScene, !viewModel.isCheckingSession else { return }
                switch screenshotScene {
                case .demoHome:
                    viewModel.startDemo()
                case .demoTrust:
                    viewModel.startDemo()
                    isTrustCenterOpen = true
                case .onboarding:
                    viewModel.enterScreenshotOnboarding()
                case nil:
                    break
                }
                hasAppliedScreenshotScene = true
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.refreshNotificationPermission()
                }
            }
        }
    }

    private var onboardingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("onboarding.hero_title"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.09, green: 0.18, blue: 0.29))

            Text(localized("onboarding.hero_body"))
                .font(.body)
                .foregroundStyle(.secondary)

            TrustCard(title: localized("onboarding.before_connect_title")) {
                TrustLine(localized("onboarding.before_connect_step_1"))
                TrustLine(localized("onboarding.before_connect_step_2"))
                TrustLine(localized("onboarding.before_connect_step_3"))
                TrustLine(localized("onboarding.before_connect_step_4"))
                TrustLine(localized("onboarding.before_connect_step_5"))
            }

            if let code = viewModel.userCode {
                TrustCard(title: localized("onboarding.finish_authorization_title")) {
                    TrustLine(localized("onboarding.enter_code"))
                    Text(code)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)

                    if let verificationURL = viewModel.verificationURL {
                        TrustLine(localized("onboarding.verification_url", verificationURL))
                    }

                    if let directVerificationURL = viewModel.directVerificationURL {
                        TrustLine(localized("onboarding.direct_verification_url", directVerificationURL))
                    }

                    if let interval = viewModel.authorizationPollIntervalSeconds,
                       let expiration = currentAuthorizationExpiration {
                        TrustLine(
                            localized(
                                "onboarding.polling_until",
                                formatInteger(Int(interval)),
                                formatInstant(expiration)
                            )
                        )
                    }

                    TrustLine(localized("onboarding.waiting_for_approval"))

                    HStack(spacing: 12) {
                        Button(localized("common.copy_code")) {
                            UIPasteboard.general.string = code
                        }
                        .buttonStyle(.bordered)

                        Button(localized("common.open_authorization_page")) {
                            openAuthorizationPage()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button(localized("common.cancel_authorization")) {
                        viewModel.cancelAuthorization()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if viewModel.errorMessage != nil && viewModel.userCode == nil {
                Button(localized("common.start_again")) {
                    viewModel.startAuthorization()
                }
                .buttonStyle(.bordered)
            }

            Button(localized("common.connect_real_debrid")) {
                viewModel.startAuthorization()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Try Demo") {
                viewModel.startDemo()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("Cue is independent and not affiliated with Real-Debrid.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            switch viewModel.notificationPermissionState {
            case .granted:
                Text(localized("onboarding.notifications_already_enabled"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if viewModel.isDemoMode {
                    Text("Demo mode shows notification permission only; prompts stay disabled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .denied:
                Button(localized("common.enable_notifications")) {
                    viewModel.requestNotifications()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(viewModel.isDemoMode)

                Button(localized("common.open_notification_settings")) {
                    viewModel.openAppSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(viewModel.isDemoMode)

                Text(localized("onboarding.notifications_disabled_help"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if viewModel.isDemoMode {
                    Text("Demo mode shows notification permission only; prompts stay disabled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .notDetermined, .unknown:
                Button(
                    viewModel.isRequestingNotifications ?
                        localized("common.enabling_notifications") :
                        localized("common.enable_notifications")
                ) {
                    viewModel.requestNotifications()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(viewModel.isDemoMode)

                Text(localized("onboarding.notifications_later"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if viewModel.isDemoMode {
                    Text("Demo mode shows notification permission only; prompts stay disabled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var accountSection: some View {
        TrustCard(title: localized("account.section_title")) {
            if let accountStatus = viewModel.accountStatus {
                TrustLine(localized("account.username", accountStatus.username ?? localized("common.unknown")))
                TrustLine(
                    localized(
                        "account.premium",
                        accountStatus.isPremium ? localized("common.active") : localized("common.inactive")
                    )
                )
                TrustLine(localized("account.state", localizedExpiryState(accountStatus.expiryState.name)))
                TrustLine(
                    localized(
                        "account.days_remaining",
                        accountStatus.remainingDays.map { formatInteger($0.intValue) } ?? localized("common.unknown")
                    )
                )
                TrustLine(
                    localized(
                        "account.expires",
                        accountStatus.expiration.map(formatInstant) ?? localized("common.unknown")
                    )
                )
                TrustLine(localized("account.last_checked", formatInstant(accountStatus.lastCheckedAt)))
            } else if viewModel.isRefreshing {
                ProgressView()
            } else {
                TrustLine(localized("account.no_data"))
            }
        }
    }

    private var actionsSection: some View {
        TrustCard(title: localized("common.actions")) {
            HStack(spacing: 12) {
                Button(
                    viewModel.isRefreshing ?
                        localized("common.refreshing_status") :
                        localized("common.refresh_status")
                ) {
                    Task { await viewModel.refreshAccount() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRefreshing)

                Button(localized("common.notifications")) {
                    viewModel.requestNotifications()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isRequestingNotifications || viewModel.isDemoMode)
            }

            if viewModel.notificationPermissionState == .denied {
                Button(localized("common.open_notification_settings")) {
                    viewModel.openAppSettings()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isDemoMode)
            }

            Button(viewModel.isDemoMode ? "End Demo" : localized("common.disconnect"), role: .destructive) {
                viewModel.disconnect()
            }
            .buttonStyle(.bordered)
        }
    }

    private var reminderSettingsSection: some View {
        TrustCard(title: localized("reminders.settings_title")) {
            Toggle(
                localized("reminders.enable"),
                isOn: Binding(
                    get: { viewModel.reminderConfig.enabled },
                    set: { viewModel.setReminderEnabled($0) }
                )
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(localized("reminders.days_before_expiry"))
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 10) {
                    ReminderDayButton(
                        label: localizedPlural("reminders.day_count", count: 7, formatInteger(7)),
                        isSelected: viewModel.reminderConfig.sevenDayReminder,
                        action: { viewModel.toggleReminderDay(7) }
                    )
                    ReminderDayButton(
                        label: localizedPlural("reminders.day_count", count: 3, formatInteger(3)),
                        isSelected: viewModel.reminderConfig.threeDayReminder,
                        action: { viewModel.toggleReminderDay(3) }
                    )
                    ReminderDayButton(
                        label: localizedPlural("reminders.day_count", count: 1, formatInteger(1)),
                        isSelected: viewModel.reminderConfig.oneDayReminder,
                        action: { viewModel.toggleReminderDay(1) }
                    )
                }

                TrustLine(localized("reminders.selected", selectedReminderDays))
            }

            Toggle(
                localized("reminders.notify_on_expiry"),
                isOn: Binding(
                    get: { viewModel.reminderConfig.notifyOnExpiry },
                    set: { viewModel.setNotifyOnExpiry($0) }
                )
            )

            Toggle(
                localized("reminders.notify_after_expiry"),
                isOn: Binding(
                    get: { viewModel.reminderConfig.notifyAfterExpiry },
                    set: { viewModel.setNotifyAfterExpiry($0) }
                )
            )
        }
    }

    private var reminderScheduleSection: some View {
        TrustCard(title: localized("reminders.schedule_title")) {
            if viewModel.accountStatus?.expiration == nil {
                TrustLine(localized("reminders.refresh_to_preview"))
            } else if !viewModel.reminderConfig.enabled {
                TrustLine(localized("reminders.turned_off"))
            } else if viewModel.isDemoMode {
                TrustLine("Notification schedule below is a preview in demo mode.")
                reminderListLines
            } else if viewModel.notificationPermissionState == .denied {
                TrustLine(localized("reminders.notifications_disabled"))
                reminderListLines
            } else if viewModel.scheduledReminders.isEmpty {
                TrustLine(localized("reminders.no_future_planned"))
            } else {
                TrustLine(localized("reminders.local_schedule_intro"))
                reminderListLines
            }
        }
    }

    @ViewBuilder
    private var reminderListLines: some View {
        if viewModel.scheduledReminders.isEmpty {
            TrustLine(localized("reminders.no_future_planned"))
        } else {
            TrustLine(localized("reminders.planned_times"))
            ForEach(Array(viewModel.scheduledReminders.enumerated()), id: \.offset) { _, reminder in
                TrustLine(localized("reminders.scheduled_item", formatInstant(reminder.fireAt), reminder.message))
            }
        }
    }

    private var trustCenterSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.isDemoMode {
                if !isScreenshotCapture {
                    MessageBanner(
                        text: "Demo mode is active. Notifications and exports stay disabled.",
                        tone: .info
                    )
                }
            }

            Text(localized("trust_center.hero_title"))
                .font(.title2.bold())
                .foregroundStyle(Color(red: 0.09, green: 0.18, blue: 0.29))

            Text(localized("trust_center.hero_body"))
                .font(.body)
                .foregroundStyle(.secondary)

            TrustCard(title: localized("trust_center.privacy_title")) {
                TrustLine(localized("trust_center.privacy_line_1"))
                TrustLine(localized("trust_center.privacy_line_2"))
                TrustLine(localized("trust_center.privacy_line_3"))
                TrustLine(localized("trust_center.privacy_line_4"))
            }

            TrustCard(title: localized("trust_center.security_title")) {
                TrustLine(localized("trust_center.security_line_1"))
                TrustLine(localized("trust_center.security_line_2_android"))
                TrustLine(localized("trust_center.security_line_2_ios"))
                TrustLine(localized("trust_center.security_line_3"))
            }

            TrustCard(title: localized("trust_center.diagnostics_title")) {
                TrustLine(localized("trust_center.diagnostics_line_1"))
                TrustLine(localized("trust_center.diagnostics_line_2"))

                HStack(spacing: 12) {
                    Button(
                        viewModel.isLoadingDiagnosticsPreview ?
                            localized("common.loading") :
                            localized("common.refresh_preview")
                    ) {
                        viewModel.loadDiagnosticsPreview()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoadingDiagnosticsPreview)

                    Button(
                        viewModel.isDemoMode ?
                            "Export Disabled" :
                        viewModel.isExporting ?
                            localized("common.exporting") :
                            localized("common.export_json")
                    ) {
                        viewModel.exportDiagnostics()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isExporting || viewModel.isDemoMode)
                }

                if viewModel.isLoadingDiagnosticsPreview && viewModel.diagnosticsPreview == nil {
                    ProgressView()
                } else {
                    Text(viewModel.diagnosticsPreview ?? localized("trust_center.preview_unavailable"))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            TrustCard(title: localized("trust_center.about_title")) {
                TrustLine(localized("trust_center.about_line_1"))
                TrustLine(localized("trust_center.about_line_2"))
                TrustLine(localized("trust_center.about_line_3"))
            }

            TrustCard(title: "Independence") {
                TrustLine("Cue is an independent companion app for Real-Debrid renewal reminders.")
                TrustLine("Cue is not affiliated with, endorsed by, or operated by Real-Debrid.")
            }

            TrustCard(title: "Links") {
                Link("Open Privacy Policy", destination: URL(string: CueExternalLinks.shared.privacyPolicyUrl)!)
                Link("Open Support", destination: URL(string: CueExternalLinks.shared.supportUrl)!)
                Link("Open Review Guide", destination: URL(string: CueExternalLinks.shared.reviewGuideUrl)!)
                Link("View Source on GitHub", destination: URL(string: CueExternalLinks.shared.sourceRepositoryUrl)!)
            }

            TrustCard(title: "Open Source Licenses") {
                TrustLine(CueOpenSourceNotices.shared.summary)
            }
        }
    }

    private var selectedReminderDays: String {
        var values: [String] = []
        if viewModel.reminderConfig.sevenDayReminder {
            values.append(formatInteger(7))
        }
        if viewModel.reminderConfig.threeDayReminder {
            values.append(formatInteger(3))
        }
        if viewModel.reminderConfig.oneDayReminder {
            values.append(formatInteger(1))
        }
        return values.isEmpty ? localized("common.none") : values.joined(separator: ", ")
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

    private func localizedExpiryState(_ state: String) -> String {
        switch state {
        case "ACTIVE":
            return localized("account.expiry_state.active")
        case "EXPIRING_SOON":
            return localized("account.expiry_state.expiring_soon")
        case "EXPIRED":
            return localized("account.expiry_state.expired")
        default:
            return localized("account.expiry_state.unknown")
        }
    }

    private func formatInstant(_ instant: Kotlinx_datetimeInstant) -> String {
        dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(instant.toEpochMilliseconds()) / 1000))
    }

    private func formatInteger(_ value: Int) -> String {
        integerFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func localized(_ key: String) -> String {
        AppL10n.text(key)
    }

    private func localized(_ key: String, _ arg0: String) -> String {
        AppL10n.text(key, arg0)
    }

    private func localized(_ key: String, _ arg0: String, _ arg1: String) -> String {
        AppL10n.text(key, arg0, arg1)
    }

    private func localizedPlural(_ key: String, count: Int, _ arg0: String) -> String {
        AppL10n.plural(key, count: count, arg0)
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = .current
    formatter.locale = .current
    formatter.timeZone = .current
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

private let integerFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = .current
    formatter.numberStyle = .decimal
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
