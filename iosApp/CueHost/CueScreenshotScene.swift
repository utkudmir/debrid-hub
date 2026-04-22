import Foundation

enum CueScreenshotScene: String {
    case onboarding = "onboarding"
    case demoHome = "demo-home"
    case demoTrust = "demo-trust"

    static var current: CueScreenshotScene? {
        if let raw = ProcessInfo.processInfo.environment["CUE_SCREENSHOT_SCENE"],
           let scene = CueScreenshotScene(rawValue: raw) {
            return scene
        }

        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--cue-screenshot-scene"),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        return CueScreenshotScene(rawValue: arguments[index + 1])
    }
}
