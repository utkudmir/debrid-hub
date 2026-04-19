import Foundation
import Shared
import UIKit
import UserNotifications

enum AuthorizationPollState: Equatable {
    case pending
    case authorized
    case expired
    case denied
    case failure(String)
    case unexpected
}

struct AuthorizationSessionState {
    let userCode: String
    let verificationURL: String
    let directVerificationURL: String?
    let expiresAt: Kotlinx_datetimeInstant?
    let pollIntervalSeconds: Int64
}

protocol IOSAppServiceProtocol: AnyObject {
    func close()
    func getReminderConfigSnapshot() async throws -> ReminderConfigSnapshot
    func isAuthenticated() async throws -> Bool
    func startAuthorization() async throws -> AuthorizationSessionState
    func pollAuthorization() async throws -> AuthorizationPollState
    func refreshAccountStatus() async throws -> AccountStatus
    func syncReminders() async throws -> Int
    func previewReminders() async throws -> [ScheduledReminder]
    func requestNotificationPermission() async throws -> Bool
    func updateReminderConfigSnapshot(snapshot: ReminderConfigSnapshot) async throws
    func disconnect() async throws
    func exportDiagnostics() async throws -> ExportedFile
    func previewDiagnostics() async throws -> String
}

protocol NotificationPermissionStateProviding {
    func currentState() async -> NotificationPermissionState
}

protocol SettingsOpening {
    func openAppSettings()
}

private final class IOSAppService: IOSAppServiceProtocol {
    private let graph: IosAppGraph

    init(appVersion: String) {
        graph = IosAppGraph(appVersion: appVersion)
    }

    func close() {
        graph.close()
    }

    func getReminderConfigSnapshot() async throws -> ReminderConfigSnapshot {
        try await graph.controller.getReminderConfigSnapshot()
    }

    func isAuthenticated() async throws -> Bool {
        let value = try await graph.controller.isAuthenticated()
        return value.boolValue
    }

    func startAuthorization() async throws -> AuthorizationSessionState {
        let session = try await graph.controller.startAuthorization()
        return AuthorizationSessionState(
            userCode: session.userCode,
            verificationURL: session.verificationUrl,
            directVerificationURL: session.directVerificationUrl,
            expiresAt: session.expiresAt,
            pollIntervalSeconds: session.pollIntervalSeconds
        )
    }

    func pollAuthorization() async throws -> AuthorizationPollState {
        let result = try await graph.controller.pollAuthorization()
        switch result {
        case is AuthPollResultPending:
            return .pending
        case is AuthPollResultAuthorized:
            return .authorized
        case is AuthPollResultExpired:
            return .expired
        case is AuthPollResultDenied:
            return .denied
        case let failure as AuthPollResultFailure:
            return .failure(failure.message)
        default:
            return .unexpected
        }
    }

    func refreshAccountStatus() async throws -> AccountStatus {
        try await graph.controller.refreshAccountStatus()
    }

    func syncReminders() async throws -> Int {
        Int(truncating: try await graph.controller.syncReminders())
    }

    func previewReminders() async throws -> [ScheduledReminder] {
        try await graph.controller.previewReminders()
    }

    func requestNotificationPermission() async throws -> Bool {
        let result = try await graph.controller.requestNotificationPermission()
        return result.boolValue
    }

    func updateReminderConfigSnapshot(snapshot: ReminderConfigSnapshot) async throws {
        try await graph.controller.updateReminderConfigSnapshot(snapshot: snapshot)
    }

    func disconnect() async throws {
        try await graph.controller.disconnect()
    }

    func exportDiagnostics() async throws -> ExportedFile {
        try await graph.controller.exportDiagnostics()
    }

    func previewDiagnostics() async throws -> String {
        try await graph.controller.previewDiagnostics()
    }
}

private struct SystemNotificationPermissionStateProvider: NotificationPermissionStateProviding {
    func currentState() async -> NotificationPermissionState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }
}

private struct SystemSettingsOpener: SettingsOpening {
    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

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
    @Published var infoMessage: String?
    @Published var diagnosticsPreview: String?
    @Published var userCode: String?
    @Published var verificationURL: String?
    @Published var directVerificationURL: String?
    @Published var authorizationExpiresAt: Kotlinx_datetimeInstant?
    @Published var authorizationPollIntervalSeconds: Int64?
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
    private let service: any IOSAppServiceProtocol
    private let notificationPermissionProvider: any NotificationPermissionStateProviding
    private let settingsOpener: any SettingsOpening
    private var isStartingAuthorization = false
    private var pollingTask: Task<Void, Never>?

    deinit {
        service.close()
    }

    init(
        service: any IOSAppServiceProtocol = IOSAppService(appVersion: "1.0.0"),
        notificationPermissionProvider: any NotificationPermissionStateProviding =
            SystemNotificationPermissionStateProvider(),
        settingsOpener: any SettingsOpening = SystemSettingsOpener(),
        autoBootstrap: Bool = true
    ) {
        self.service = service
        self.notificationPermissionProvider = notificationPermissionProvider
        self.settingsOpener = settingsOpener

        if autoBootstrap {
            Task {
                await bootstrap()
            }
        } else {
            isCheckingSession = false
        }
    }

    func bootstrap() async {
        await refreshNotificationPermissionState()
        do {
            reminderConfig = try await service.getReminderConfigSnapshot()
            isAuthenticated = try await service.isAuthenticated()
            isCheckingSession = false
            if isAuthenticated {
                await refreshAccount()
            }
        } catch {
            isCheckingSession = false
            showError(error)
        }
    }

    func startAuthorization() {
        guard !isStartingAuthorization, pollingTask == nil else { return }
        isStartingAuthorization = true
        pollingTask?.cancel()
        clearMessages()
        clearAuthorizationSession()
        Task {
            do {
                let session = try await service.startAuthorization()
                isStartingAuthorization = false
                userCode = session.userCode
                verificationURL = session.verificationURL
                directVerificationURL = session.directVerificationURL
                authorizationExpiresAt = session.expiresAt
                authorizationPollIntervalSeconds = session.pollIntervalSeconds
                if let browserURL = URL(string: session.directVerificationURL ?? session.verificationURL) {
                    authorizationBrowserTarget = AuthorizationBrowserTarget(url: browserURL)
                }
                pollAuthorization(interval: session.pollIntervalSeconds)
            } catch {
                isStartingAuthorization = false
                if error is CancellationError { return }
                clearAuthorizationSession()
                showError(error)
            }
        }
    }

    func cancelAuthorization() {
        isStartingAuthorization = false
        pollingTask?.cancel()
        pollingTask = nil
        clearAuthorizationSession()
    }

    func refreshAccount() async {
        isRefreshing = true
        defer { isRefreshing = false }
        errorMessage = nil
        do {
            await refreshNotificationPermissionState()
            reminderConfig = try await service.getReminderConfigSnapshot()
            accountStatus = try await service.refreshAccountStatus()
            _ = try await service.syncReminders()
            scheduledReminders = try await service.previewReminders()
        } catch {
            showError(error)
        }
    }

    func requestNotifications() {
        Task {
            isRequestingNotifications = true
            defer { isRequestingNotifications = false }
            clearMessages()
            do {
                let granted = try await service.requestNotificationPermission()
                await refreshNotificationPermissionState()
                if isAuthenticated {
                    if granted {
                        _ = try await service.syncReminders()
                    }
                    scheduledReminders = try await service.previewReminders()
                }
                if granted {
                    infoMessage = "Notifications enabled."
                } else {
                    infoMessage = "Notifications remain disabled. Open system settings if you want reminder alerts."
                }
            } catch {
                await refreshNotificationPermissionState()
                showError(error)
            }
        }
    }

    func openAppSettings() {
        settingsOpener.openAppSettings()
    }

    func exportDiagnostics() {
        Task {
            isExporting = true
            defer { isExporting = false }
            clearMessages()
            do {
                let file = try await service.exportDiagnostics()
                infoMessage = "Diagnostics exported to \(file.location)"
            } catch {
                showError(error)
            }
        }
    }

    func loadDiagnosticsPreview() {
        guard !isLoadingDiagnosticsPreview else { return }
        isLoadingDiagnosticsPreview = true
        Task {
            defer { isLoadingDiagnosticsPreview = false }
            errorMessage = nil
            do {
                diagnosticsPreview = try await service.previewDiagnostics()
            } catch {
                showError(error)
            }
        }
    }

    func disconnect() {
        isStartingAuthorization = false
        pollingTask?.cancel()
        pollingTask = nil
        clearMessages()
        clearAuthorizationSession()
        Task {
            do {
                try await service.disconnect()
                isAuthenticated = false
                accountStatus = nil
                diagnosticsPreview = nil
                scheduledReminders = []
                reminderConfig = try await service.getReminderConfigSnapshot()
                clearAuthorizationSession()
                infoMessage = "Disconnected from Real-Debrid."
            } catch {
                showError(error)
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
            defer { pollingTask = nil }
            while !Task.isCancelled {
                do {
                    let result = try await service.pollAuthorization()
                    switch result {
                    case .pending:
                        try? await Task.sleep(for: .seconds(Double(interval)))
                    case .authorized:
                        isAuthenticated = true
                        clearAuthorizationSession()
                        infoMessage = "Authorization completed."
                        await refreshAccount()
                        return
                    case .expired:
                        clearAuthorizationSession()
                        showErrorMessage("The device authorization session expired.")
                        return
                    case .denied:
                        clearAuthorizationSession()
                        showErrorMessage("Real-Debrid denied the authorization request.")
                        return
                    case let .failure(message):
                        clearAuthorizationSession()
                        showErrorMessage(message)
                        return
                    case .unexpected:
                        clearAuthorizationSession()
                        showErrorMessage("Unexpected authorization state.")
                        return
                    }
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        return
                    }
                    clearAuthorizationSession()
                    showError(error)
                    return
                }
            }
        }
    }

    private func refreshNotificationPermissionState() async {
        notificationPermissionState = await notificationPermissionProvider.currentState()
    }

    private func updateReminderConfig(_ updated: ReminderConfigSnapshot) {
        reminderConfig = updated
        Task {
            do {
                errorMessage = nil
                try await service.updateReminderConfigSnapshot(snapshot: updated)
                if isAuthenticated {
                    await refreshNotificationPermissionState()
                    _ = try await service.syncReminders()
                    scheduledReminders = try await service.previewReminders()
                }
            } catch {
                showError(error)
            }
        }
    }

    private func clearAuthorizationSession() {
        userCode = nil
        verificationURL = nil
        directVerificationURL = nil
        authorizationExpiresAt = nil
        authorizationPollIntervalSeconds = nil
        authorizationBrowserTarget = nil
    }

    private func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    private func showError(_ error: Error) {
        infoMessage = nil
        errorMessage = presentableMessage(for: error)
    }

    private func showErrorMessage(_ message: String) {
        infoMessage = nil
        errorMessage = message
    }

    private func presentableMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorSecureConnectionFailed {
            return secureConnectionFailureMessage
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
            return secureConnectionFailureMessage
        }

        if message.localizedCaseInsensitiveContains("unable to resolve host") ||
            message.localizedCaseInsensitiveContains("failed to connect") ||
            message.localizedCaseInsensitiveContains("network is unreachable") ||
            message.localizedCaseInsensitiveContains("timed out") {
            return "Couldn't reach Real-Debrid. Check your internet connection or try a different network."
        }

        return message
    }

    private var secureConnectionFailureMessage: String {
        "Secure connection to Real-Debrid failed. Your network appears to be intercepting " +
            "or downgrading HTTPS traffic to api.real-debrid.com. Disable captive portals, " +
            "VPNs, secure web gateways, or TLS inspection, or try a different network."
    }
}
