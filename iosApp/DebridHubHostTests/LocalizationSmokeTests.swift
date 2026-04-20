import XCTest

#if canImport(DebridHub)
@testable import DebridHub
#elseif canImport(DebridHubHost)
@testable import DebridHubHost
#endif

final class LocalizationSmokeTests: XCTestCase {
    override func tearDown() {
        AppL10n.overrideLanguageTags = nil
        super.tearDown()
    }

    func testLocalizedGermanBackLabel() {
        AppL10n.overrideLanguageTags = ["de-DE"]

        XCTAssertEqual("Zurück", AppL10n.text("common.back"))
    }

    func testLocalizedFrenchPluralReminderMessage() {
        AppL10n.overrideLanguageTags = ["fr"]

        XCTAssertEqual(
            "Votre abonnement Real-Debrid expire dans 2 jours",
            AppL10n.plural("reminders.notification.expires_in", count: 2, "2")
        )
    }
}
