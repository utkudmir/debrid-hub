import XCTest
import Shared

#if canImport(DebridHub)
@testable import DebridHub
#elseif canImport(DebridHubHost)
@testable import DebridHubHost
#endif

final class IOSAppViewModelTests: XCTestCase {
    func testStartAuthorizationFailureSurfacesError() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 10
            ),
            pollResults: [.pending]
        )
        service.startAuthorizationResult = .failure(TestError("authorization unavailable"))

        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.startAuthorization()
        }
        await waitUntil {
            await MainActor.run { viewModel.errorMessage != nil }
        }

        await MainActor.run {
            XCTAssertEqual("authorization unavailable", viewModel.errorMessage)
            XCTAssertNil(viewModel.userCode)
            XCTAssertNil(viewModel.authorizationBrowserTarget)
        }
    }

    func testBootstrapLoadsReminderConfigAndPermissionState() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 10
            ),
            pollResults: [.pending]
        )
        service.reminderConfigSnapshot = ReminderConfigSnapshot(
            enabled: true,
            sevenDayReminder: false,
            threeDayReminder: true,
            oneDayReminder: false,
            notifyOnExpiry: true,
            notifyAfterExpiry: true
        )

        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .granted),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: true
            )
        }

        await waitUntil {
            await MainActor.run { !viewModel.isCheckingSession }
        }

        await MainActor.run {
            XCTAssertFalse(viewModel.isAuthenticated)
            XCTAssertEqual(.granted, viewModel.notificationPermissionState)
            XCTAssertEqual(false, viewModel.reminderConfig.sevenDayReminder)
            XCTAssertEqual(true, viewModel.reminderConfig.notifyAfterExpiry)
        }
    }

    func testBootstrapWithAuthenticatedSessionRefreshesAccountAndReminders() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 10
            ),
            pollResults: [.pending]
        )
        service.isAuthenticatedValue = true
        service.refreshAccountStatusResult = .success(makeSampleAccountStatus())
        service.previewRemindersResult = .success([
            ScheduledReminder(
                fireAt: Kotlinx_datetimeInstant.companion.fromEpochSeconds(
                    epochSeconds: 1_776_675_600,
                    nanosecondAdjustment: 0
                ),
                message: "3 days left"
            )
        ])

        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .granted),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: true
            )
        }

        await waitUntil {
            await MainActor.run {
                !viewModel.isCheckingSession && viewModel.accountStatus != nil
            }
        }

        await MainActor.run {
            XCTAssertTrue(viewModel.isAuthenticated)
            XCTAssertNotNil(viewModel.accountStatus)
            XCTAssertEqual(1, viewModel.scheduledReminders.count)
            XCTAssertEqual(.granted, viewModel.notificationPermissionState)
            XCTAssertEqual(1, service.refreshAccountStatusCallCount)
            XCTAssertEqual(1, service.syncRemindersCallCount)
            XCTAssertEqual(1, service.previewRemindersCallCount)
        }
    }

    func testStartAuthorizationSetsSessionState() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: "https://real-debrid.com/device/confirm",
                expiresAt: nil,
                pollIntervalSeconds: 10
            ),
            pollResults: [.pending]
        )
        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.startAuthorization()
        }
        await waitUntil {
            await MainActor.run {
                viewModel.userCode == "ABCD-1234" &&
                    viewModel.verificationURL == "https://real-debrid.com/device" &&
                    viewModel.directVerificationURL == "https://real-debrid.com/device/confirm" &&
                    viewModel.authorizationBrowserTarget?.url.absoluteString == "https://real-debrid.com/device/confirm"
            }
        }

        await MainActor.run {
            XCTAssertEqual("ABCD-1234", viewModel.userCode)
            XCTAssertEqual("https://real-debrid.com/device", viewModel.verificationURL)
            XCTAssertEqual("https://real-debrid.com/device/confirm", viewModel.directVerificationURL)
            XCTAssertEqual(10, viewModel.authorizationPollIntervalSeconds)
            viewModel.cancelAuthorization()
        }
    }

    func testCancelAuthorizationStopsPollingAndKeepsUserUnauthenticated() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: "https://real-debrid.com/device/confirm",
                expiresAt: nil,
                pollIntervalSeconds: 1
            ),
            pollResults: [.pending, .authorized]
        )
        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.startAuthorization()
        }
        await waitUntil {
            await MainActor.run { viewModel.userCode != nil }
        }

        await MainActor.run {
            viewModel.cancelAuthorization()
        }

        try? await Task.sleep(nanoseconds: 1_100_000_000)

        await MainActor.run {
            XCTAssertFalse(viewModel.isAuthenticated)
            XCTAssertNil(viewModel.userCode)
            XCTAssertNil(viewModel.authorizationBrowserTarget)
            XCTAssertEqual(1, service.pollAuthorizationCallCount)
            XCTAssertEqual(0, service.refreshAccountStatusCallCount)
        }
    }

    func testRequestNotificationsShowsEnabledMessageWhenGranted() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 10
            ),
            pollResults: [.pending]
        )
        service.requestNotificationPermissionResult = .success(true)

        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .granted),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.requestNotifications()
        }
        await waitUntil {
            await MainActor.run { viewModel.infoMessage != nil }
        }

        await MainActor.run {
            XCTAssertEqual("Notifications enabled.", viewModel.infoMessage)
            XCTAssertEqual(.granted, viewModel.notificationPermissionState)
            XCTAssertEqual(1, service.requestNotificationPermissionCallCount)
        }
    }

    func testRequestNotificationsShowsGuidanceWhenDenied() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 10
            ),
            pollResults: [.pending]
        )
        service.requestNotificationPermissionResult = .success(false)

        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .denied),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.requestNotifications()
        }
        await waitUntil {
            await MainActor.run { viewModel.infoMessage != nil }
        }

        await MainActor.run {
            XCTAssertEqual(
                "Notifications remain disabled. Open system settings if you want reminder alerts.",
                viewModel.infoMessage
            )
            XCTAssertEqual(.denied, viewModel.notificationPermissionState)
        }
    }

    func testRequestNotificationsFailureSurfacesError() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 10
            ),
            pollResults: [.pending]
        )
        service.requestNotificationPermissionResult = .failure(TestError("permission failed"))

        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.requestNotifications()
        }
        await waitUntil {
            await MainActor.run { viewModel.errorMessage != nil }
        }

        await MainActor.run {
            XCTAssertEqual("permission failed", viewModel.errorMessage)
        }
    }

    func testLoadDiagnosticsPreviewFailureSurfacesError() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 10
            ),
            pollResults: [.pending]
        )
        service.previewDiagnosticsResult = .failure(TestError("preview unavailable"))

        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.loadDiagnosticsPreview()
        }
        await waitUntil {
            await MainActor.run { viewModel.errorMessage != nil }
        }

        await MainActor.run {
            XCTAssertEqual("preview unavailable", viewModel.errorMessage)
            XCTAssertFalse(viewModel.isLoadingDiagnosticsPreview)
        }
    }

    func testLoadDiagnosticsPreviewSuccessSetsPreviewContent() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 10
            ),
            pollResults: [.pending]
        )
        service.previewDiagnosticsResult = .success("{\"os\":\"iOS 18\"}")

        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.loadDiagnosticsPreview()
        }
        await waitUntil {
            await MainActor.run { viewModel.diagnosticsPreview != nil }
        }

        await MainActor.run {
            XCTAssertEqual("{\"os\":\"iOS 18\"}", viewModel.diagnosticsPreview)
            XCTAssertFalse(viewModel.isLoadingDiagnosticsPreview)
            XCTAssertNil(viewModel.errorMessage)
        }
    }

    func testExportDiagnosticsSuccessShowsInfoMessage() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 10
            ),
            pollResults: [.pending]
        )
        service.exportDiagnosticsResult = .success(
            ExportedFile(displayName: "diagnostics.json", location: "/tmp/diagnostics.json")
        )
        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.exportDiagnostics()
        }
        await waitUntil {
            await MainActor.run { viewModel.infoMessage != nil }
        }

        await MainActor.run {
            XCTAssertEqual("Diagnostics exported to /tmp/diagnostics.json", viewModel.infoMessage)
        }
    }

    func testExportDiagnosticsFailureSurfacesError() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 10
            ),
            pollResults: [.pending]
        )
        service.exportDiagnosticsResult = .failure(TestError("disk full"))

        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.exportDiagnostics()
        }
        await waitUntil {
            await MainActor.run { viewModel.errorMessage != nil }
        }

        await MainActor.run {
            XCTAssertEqual("disk full", viewModel.errorMessage)
        }
    }

    func testDisconnectClearsAuthorizationSessionAndResetsState() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: "https://real-debrid.com/device/confirm",
                expiresAt: nil,
                pollIntervalSeconds: 100
            ),
            pollResults: [.pending]
        )
        service.reminderConfigSnapshot = ReminderConfigSnapshot(
            enabled: false,
            sevenDayReminder: false,
            threeDayReminder: true,
            oneDayReminder: true,
            notifyOnExpiry: true,
            notifyAfterExpiry: false
        )
        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.startAuthorization()
        }
        await waitUntil {
            await MainActor.run { viewModel.userCode != nil }
        }

        await MainActor.run {
            viewModel.disconnect()
        }
        await waitUntil {
            await MainActor.run { viewModel.infoMessage == "Disconnected from Real-Debrid." }
        }

        await MainActor.run {
            XCTAssertNil(viewModel.userCode)
            XCTAssertNil(viewModel.verificationURL)
            XCTAssertNil(viewModel.directVerificationURL)
            XCTAssertNil(viewModel.authorizationBrowserTarget)
            XCTAssertFalse(viewModel.isAuthenticated)
            XCTAssertFalse(viewModel.reminderConfig.enabled)
            XCTAssertEqual(1, service.disconnectCallCount)
        }
    }

    func testRefreshAccountFailureMapsNetworkErrorMessage() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 10
            ),
            pollResults: [.pending]
        )
        service.refreshAccountStatusResult = .failure(TestError("Unable to resolve host api.real-debrid.com"))

        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await viewModel.refreshAccount()

        await MainActor.run {
            XCTAssertEqual(
                "Couldn't reach Real-Debrid. Check your internet connection or try a different network.",
                viewModel.errorMessage
            )
            XCTAssertFalse(viewModel.isRefreshing)
        }
    }

    func testSetReminderEnabledPersistsUpdatedConfig() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 10
            ),
            pollResults: [.pending]
        )

        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.setReminderEnabled(false)
        }
        await waitUntil {
            await MainActor.run { service.updatedReminderSnapshots.count == 1 }
        }

        await MainActor.run {
            XCTAssertFalse(viewModel.reminderConfig.enabled)
            XCTAssertFalse(service.updatedReminderSnapshots.last?.enabled ?? true)
        }
    }

    func testPollAuthorizationAuthorizedCompletesFlowAndClearsOnboarding() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: "https://real-debrid.com/device/confirm",
                expiresAt: nil,
                pollIntervalSeconds: 1
            ),
            pollResults: [.authorized]
        )
        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .granted),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.startAuthorization()
        }
        await waitUntil {
            await MainActor.run { service.refreshAccountStatusCallCount == 1 }
        }

        await MainActor.run {
            XCTAssertTrue(viewModel.isAuthenticated)
            XCTAssertNil(viewModel.userCode)
            XCTAssertNil(viewModel.authorizationBrowserTarget)
            XCTAssertEqual(1, service.refreshAccountStatusCallCount)
        }
    }

    func testPollAuthorizationDeniedClearsSessionAndSurfacesError() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 1
            ),
            pollResults: [.denied]
        )
        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.startAuthorization()
        }
        await waitUntil {
            await MainActor.run { viewModel.errorMessage != nil }
        }

        await MainActor.run {
            XCTAssertEqual("Real-Debrid denied the authorization request.", viewModel.errorMessage)
            XCTAssertNil(viewModel.userCode)
            XCTAssertNil(viewModel.verificationURL)
            XCTAssertNil(viewModel.directVerificationURL)
            XCTAssertNil(viewModel.authorizationBrowserTarget)
        }
    }

    func testPollAuthorizationExpiredClearsSessionAndSurfacesError() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 1
            ),
            pollResults: [.expired]
        )
        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.startAuthorization()
        }
        await waitUntil {
            await MainActor.run { viewModel.errorMessage != nil }
        }

        await MainActor.run {
            XCTAssertEqual("The device authorization session expired.", viewModel.errorMessage)
            XCTAssertNil(viewModel.userCode)
            XCTAssertNil(viewModel.authorizationBrowserTarget)
        }
    }

    func testPollAuthorizationFailureClearsSessionAndSurfacesError() async {
        let service = FakeIOSAppService(
            startSession: AuthorizationSessionState(
                userCode: "ABCD-1234",
                verificationURL: "https://real-debrid.com/device",
                directVerificationURL: nil,
                expiresAt: nil,
                pollIntervalSeconds: 1
            ),
            pollResults: [.failure("Temporary authorization outage")]
        )
        let viewModel = await MainActor.run {
            IOSAppViewModel(
                service: service,
                notificationPermissionProvider: StubNotificationPermissionStateProvider(state: .unknown),
                settingsOpener: StubSettingsOpener(),
                autoBootstrap: false
            )
        }

        await MainActor.run {
            viewModel.startAuthorization()
        }
        await waitUntil {
            await MainActor.run { viewModel.errorMessage != nil }
        }

        await MainActor.run {
            XCTAssertEqual("Temporary authorization outage", viewModel.errorMessage)
            XCTAssertNil(viewModel.userCode)
            XCTAssertNil(viewModel.authorizationBrowserTarget)
        }
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping () async -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for expected state transition")
    }
}

private final class FakeIOSAppService: IOSAppServiceProtocol {
    private let startSession: AuthorizationSessionState
    private var pollResults: [AuthorizationPollState]
    var isAuthenticatedValue: Bool = false
    var startAuthorizationResult: Result<AuthorizationSessionState, Error>
    var reminderConfigSnapshot = ReminderConfigSnapshot(
        enabled: true,
        sevenDayReminder: true,
        threeDayReminder: true,
        oneDayReminder: true,
        notifyOnExpiry: true,
        notifyAfterExpiry: false
    )
    var refreshAccountStatusResult: Result<AccountStatus, Error> = .failure(FakeServiceError.unexpectedCall)
    var requestNotificationPermissionResult: Result<Bool, Error> = .success(false)
    var exportDiagnosticsResult: Result<ExportedFile, Error> = .success(
        ExportedFile(displayName: "diagnostics.json", location: "/tmp/diagnostics.json")
    )
    var previewDiagnosticsResult: Result<String, Error> = .success("{}")
    var updatedReminderSnapshots: [ReminderConfigSnapshot] = []
    var syncRemindersResult: Result<Int, Error> = .success(0)
    var previewRemindersResult: Result<[ScheduledReminder], Error> = .success([])
    var pollAuthorizationCallCount = 0
    var refreshAccountStatusCallCount = 0
    var syncRemindersCallCount = 0
    var previewRemindersCallCount = 0
    var requestNotificationPermissionCallCount = 0
    var disconnectCallCount = 0

    init(
        startSession: AuthorizationSessionState,
        pollResults: [AuthorizationPollState]
    ) {
        self.startSession = startSession
        self.pollResults = pollResults
        self.startAuthorizationResult = .success(startSession)
    }

    func close() {}

    func getReminderConfigSnapshot() async throws -> ReminderConfigSnapshot {
        reminderConfigSnapshot
    }

    func isAuthenticated() async throws -> Bool { isAuthenticatedValue }

    func startAuthorization() async throws -> AuthorizationSessionState {
        try startAuthorizationResult.get()
    }

    func pollAuthorization() async throws -> AuthorizationPollState {
        pollAuthorizationCallCount += 1
        guard !pollResults.isEmpty else { return .pending }
        return pollResults.removeFirst()
    }

    func refreshAccountStatus() async throws -> AccountStatus {
        refreshAccountStatusCallCount += 1
        return try refreshAccountStatusResult.get()
    }

    func syncReminders() async throws -> Int {
        syncRemindersCallCount += 1
        return try syncRemindersResult.get()
    }

    func previewReminders() async throws -> [ScheduledReminder] {
        previewRemindersCallCount += 1
        return try previewRemindersResult.get()
    }

    func requestNotificationPermission() async throws -> Bool {
        requestNotificationPermissionCallCount += 1
        return try requestNotificationPermissionResult.get()
    }

    func updateReminderConfigSnapshot(snapshot: ReminderConfigSnapshot) async throws {
        updatedReminderSnapshots.append(snapshot)
    }

    func disconnect() async throws {
        disconnectCallCount += 1
    }

    func exportDiagnostics() async throws -> ExportedFile {
        try exportDiagnosticsResult.get()
    }

    func previewDiagnostics() async throws -> String {
        try previewDiagnosticsResult.get()
    }
}

private enum FakeServiceError: Error {
    case unexpectedCall
}

private struct TestError: LocalizedError {
    private let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private func makeSampleAccountStatus() -> AccountStatus {
    AccountStatus(
        username: "sample-user",
        expiration: Kotlinx_datetimeInstant.companion.fromEpochSeconds(
            epochSeconds: 1_776_934_800,
            nanosecondAdjustment: 0
        ),
        remainingDays: KotlinInt(int: 5),
        premiumSeconds: KotlinLong(longLong: 432000),
        isPremium: true,
        lastCheckedAt: Kotlinx_datetimeInstant.companion.fromEpochSeconds(
            epochSeconds: 1_776_502_800,
            nanosecondAdjustment: 0
        ),
        expiryState: ExpiryState.active
    )
}

private struct StubNotificationPermissionStateProvider: NotificationPermissionStateProviding {
    let state: NotificationPermissionState

    func currentState() async -> NotificationPermissionState {
        state
    }
}

private struct StubSettingsOpener: SettingsOpening {
    func openAppSettings() {}
}
