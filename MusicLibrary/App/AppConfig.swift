import Foundation

/// Values that identify the app. The display name and bundle ID themselves are
/// set in `Config/App.xcconfig`; this reads them back at runtime.
enum AppConfig {
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Music Library"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
