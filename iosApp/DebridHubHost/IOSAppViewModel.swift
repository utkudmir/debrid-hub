import Foundation
import Shared
import UIKit
import UserNotifications

struct AuthorizationBrowserTarget: Identifiable, Equatable {
    let url: URL
    var id: String { url.absoluteString }
}

enum NotificationPermissionState {
    case unknown
    case notDetermined
    case granted
    case denied
}

@MainActor
final class IOSAppViewModel: ObservableObject {
    @Published var isCheckingSession = true
    @Published var isAuthenticated = false
    @Published var isRefreshing = false
    @Published var isExporting = false
    @Published var isLoadingDiagnosticsPreview = false
    @Published var isRequestingNotifications = false
    @Published var errorMessage: String?
    @Published var diagnosticsPreview: String?
    @Published var userCode: String?
    @Published var verificationURL: String?
    @Published var directVerificationURL: String?
    @Published var authorizationBrowserTarget: AuthorizationBrowserTarget?
    @Published var accountStatus: AccountStatus?
    @Published var scheduledReminders: [ScheduledReminder] = []
    @Published var notificationPermissionState: NotificationPermissionState = .unknown
    @Published var reminderConfig = ReminderConfigSnapshot(
        enabled: true,
        sevenDayReminder: true,
        threeDayReminder: true,
        oneDayReminder: true,
        notifyOnExpiry: true,
        notifyAfterExpiry: false
    )
    private let graph = IosAppGraph(appVersion: "1.0.0")
    private var pollingTask: Task<Void, Never>?

    deinit {
        graph.close()
    }

    init() {
        Task {
            await bootstrap()
        }
    }

    func bootstrap() async {
        await refreshNotificationPermissionState()
        do {
            reminderConfig = try await graph.controller.getReminderConfigSnapshot()
            let authState = try await graph.controller.isAuthenticated()
            isAuthenticated = authState.boolValue
            isCheckingSession = false
            if isAuthenticated {
                await refreshAccount()
            }
        } catch {
            isCheckingSession = false
            errorMessage = presentableMessage(for: error)
        }
    }

    func startAuthorization() {
        pollingTask?.cancel()
        Task {
            do {
                let session = try await graph.controller.startAuthorization()
                userCode = session.userCode
                verificationURL = session.verificationUrl
                directVerificationURL = session.directVerificationUrl
                if let browserURL = URL(string: session.directVerificationUrl ?? session.verificationUrl) {
                    authorizationBrowserTarget = AuthorizationBrowserTarget(url: browserURL)
                }
                pollAuthorization(interval: session.pollIntervalSeconds)
            } catch {
                errorMessage = presentableMessage(for: error)
            }
        }
    }

    func cancelAuthorization() {
        pollingTask?.cancel()
        userCode = nil
        verificationURL = nil
        directVerificationURL = nil
        authorizationBrowserTarget = nil
    }

    func refreshAccount() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            await refreshNotificationPermissionState()
            reminderConfig = try await graph.controller.getReminderConfigSnapshot()
            accountStatus = try await graph.controller.refreshAccountStatus()
            _ = try await graph.controller.syncReminders()
            scheduledReminders = try await graph.controller.previewReminders()
        } catch {
            errorMessage = presentableMessage(for: error)
        }
    }

    func requestNotifications() {
        Task {
            isRequestingNotifications = true
            defer { isRequestingNotifications = false }
            do {
                _ = try await graph.controller.requestNotificationPermission()
                await refreshNotificationPermissionState()
                if isAuthenticated {
                    _ = try await graph.controller.syncReminders()
                    scheduledReminders = try await graph.controller.previewReminders()
                }
            } catch {
                await refreshNotificationPermissionState()
                errorMessage = presentableMessage(for: error)
            }
        }
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func exportDiagnostics() {
        Task {
            isExporting = true
            defer { isExporting = false }
            do {
                let file = try await graph.controller.exportDiagnostics()
                errorMessage = "Diagnostics exported to \(file.location)"
            } catch {
                errorMessage = presentableMessage(for: error)
            }
        }
    }

    func loadDiagnosticsPreview() {
        guard !isLoadingDiagnosticsPreview else { return }
        Task {
            isLoadingDiagnosticsPreview = true
            defer { isLoadingDiagnosticsPreview = false }
            do {
                diagnosticsPreview = try await graph.controller.previewDiagnostics()
            } catch {
                errorMessage = presentableMessage(for: error)
            }
        }
    }

    func disconnect() {
        pollingTask?.cancel()
        Task {
            do {
                try await graph.controller.disconnect()
                isAuthenticated = false
                accountStatus = nil
                diagnosticsPreview = nil
                scheduledReminders = []
                reminderConfig = try await graph.controller.getReminderConfigSnapshot()
                userCode = nil
                verificationURL = nil
                directVerificationURL = nil
                authorizationBrowserTarget = nil
            } catch {
                errorMessage = presentableMessage(for: error)
            }
        }
    }

    func setReminderEnabled(_ enabled: Bool) {
        updateReminderConfig(reminderConfig.doCopy(
            enabled: enabled,
            sevenDayReminder: reminderConfig.sevenDayReminder,
            threeDayReminder: reminderConfig.threeDayReminder,
            oneDayReminder: reminderConfig.oneDayReminder,
            notifyOnExpiry: reminderConfig.notifyOnExpiry,
            notifyAfterExpiry: reminderConfig.notifyAfterExpiry
        ))
    }

    func toggleReminderDay(_ day: Int) {
        let updated: ReminderConfigSnapshot
        switch day {
        case 7:
            updated = reminderConfig.doCopy(
                enabled: reminderConfig.enabled,
                sevenDayReminder: !reminderConfig.sevenDayReminder,
                threeDayReminder: reminderConfig.threeDayReminder,
                oneDayReminder: reminderConfig.oneDayReminder,
                notifyOnExpiry: reminderConfig.notifyOnExpiry,
                notifyAfterExpiry: reminderConfig.notifyAfterExpiry
            )
        case 3:
            updated = reminderConfig.doCopy(
                enabled: reminderConfig.enabled,
                sevenDayReminder: reminderConfig.sevenDayReminder,
                threeDayReminder: !reminderConfig.threeDayReminder,
                oneDayReminder: reminderConfig.oneDayReminder,
                notifyOnExpiry: reminderConfig.notifyOnExpiry,
                notifyAfterExpiry: reminderConfig.notifyAfterExpiry
            )
        case 1:
            updated = reminderConfig.doCopy(
                enabled: reminderConfig.enabled,
                sevenDayReminder: reminderConfig.sevenDayReminder,
                threeDayReminder: reminderConfig.threeDayReminder,
                oneDayReminder: !reminderConfig.oneDayReminder,
                notifyOnExpiry: reminderConfig.notifyOnExpiry,
                notifyAfterExpiry: reminderConfig.notifyAfterExpiry
            )
        default:
            return
        }
        updateReminderConfig(updated)
    }

    func setNotifyOnExpiry(_ enabled: Bool) {
        updateReminderConfig(reminderConfig.doCopy(
            enabled: reminderConfig.enabled,
            sevenDayReminder: reminderConfig.sevenDayReminder,
            threeDayReminder: reminderConfig.threeDayReminder,
            oneDayReminder: reminderConfig.oneDayReminder,
            notifyOnExpiry: enabled,
            notifyAfterExpiry: reminderConfig.notifyAfterExpiry
        ))
    }

    func setNotifyAfterExpiry(_ enabled: Bool) {
        updateReminderConfig(reminderConfig.doCopy(
            enabled: reminderConfig.enabled,
            sevenDayReminder: reminderConfig.sevenDayReminder,
            threeDayReminder: reminderConfig.threeDayReminder,
            oneDayReminder: reminderConfig.oneDayReminder,
            notifyOnExpiry: reminderConfig.notifyOnExpiry,
            notifyAfterExpiry: enabled
        ))
    }

    private func pollAuthorization(interval: Int64) {
        pollingTask = Task {
            while !Task.isCancelled {
                do {
                    let result = try await graph.controller.pollAuthorization()
                    switch result {
                    case is AuthPollResultPending:
                        try? await Task.sleep(for: .seconds(Double(interval)))
                    case is AuthPollResultAuthorized:
                        isAuthenticated = true
                        userCode = nil
                        verificationURL = nil
                        directVerificationURL = nil
                        authorizationBrowserTarget = nil
                        await refreshAccount()
                        return
                    case is AuthPollResultExpired:
                        authorizationBrowserTarget = nil
                        errorMessage = "The device authorization session expired."
                        return
                    case is AuthPollResultDenied:
                        authorizationBrowserTarget = nil
                        errorMessage = "Real-Debrid denied the authorization request."
                        return
                    case let failure as AuthPollResultFailure:
                        authorizationBrowserTarget = nil
                        errorMessage = failure.message
                        return
                    default:
                        errorMessage = "Unexpected authorization state."
                        return
                    }
                } catch {
                    errorMessage = presentableMessage(for: error)
                    return
                }
            }
        }
    }

    private func refreshNotificationPermissionState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationPermissionState = .granted
        case .denied:
            notificationPermissionState = .denied
        case .notDetermined:
            notificationPermissionState = .notDetermined
        @unknown default:
            notificationPermissionState = .unknown
        }
    }

    private func updateReminderConfig(_ updated: ReminderConfigSnapshot) {
        reminderConfig = updated
        Task {
            do {
                try await graph.controller.updateReminderConfigSnapshot(snapshot: updated)
                if isAuthenticated {
                    await refreshAccount()
                }
            } catch {
                errorMessage = presentableMessage(for: error)
            }
        }
    }

    private func presentableMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorSecureConnectionFailed {
            return "Secure connection to Real-Debrid failed. Your network appears to be intercepting or downgrading HTTPS traffic to api.real-debrid.com. Disable captive portals, VPNs, secure web gateways, or TLS inspection, or try a different network."
        }

        let message = nsError.localizedDescription
        if message.localizedCaseInsensitiveContains("tls") ||
            message.localizedCaseInsensitiveContains("ssl") ||
            message.localizedCaseInsensitiveContains("proxy") ||
            message.localizedCaseInsensitiveContains("plaintext connection") ||
            message.localizedCaseInsensitiveContains("wrong version number") ||
            message.localizedCaseInsensitiveContains("protocol version") ||
            message.localizedCaseInsensitiveContains("handshake") ||
            message.localizedCaseInsensitiveContains("middlebox") {
            return "Secure connection to Real-Debrid failed. Your network appears to be intercepting or downgrading HTTPS traffic to api.real-debrid.com. Disable captive portals, VPNs, secure web gateways, or TLS inspection, or try a different network."
        }

        if message.localizedCaseInsensitiveContains("unable to resolve host") ||
            message.localizedCaseInsensitiveContains("failed to connect") ||
            message.localizedCaseInsensitiveContains("network is unreachable") ||
            message.localizedCaseInsensitiveContains("timed out") {
            return "Couldn't reach Real-Debrid. Check your internet connection or try a different network."
        }

        return message
    }
}
