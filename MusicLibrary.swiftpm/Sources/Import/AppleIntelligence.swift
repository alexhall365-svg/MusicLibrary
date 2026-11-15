import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleIntelligenceStatus: Equatable {
    case available
    case unavailable(String)

    var isAvailable: Bool { self == .available }

    var message: String {
        switch self {
        case .available: return "Ready"
        case .unavailable(let reason): return reason
        }
    }
}

/// Entry point for Apple's on-device language model (Foundation Models, iOS 26+).
/// Everything here degrades gracefully on older systems or builds made with an
/// older SDK.
enum AppleIntelligence {
    static var status: AppleIntelligenceStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable("This device doesn't support Apple Intelligence.")
                case .appleIntelligenceNotEnabled:
                    return .unavailable("Turn on Apple Intelligence in Settings → Apple Intelligence & Siri, then come back.")
                case .modelNotReady:
                    return .unavailable("Apple Intelligence is still getting ready (downloading). Try again a little later.")
                @unknown default:
                    return .unavailable("Apple Intelligence isn't available right now.")
                }
            @unknown default:
                return .unavailable("Apple Intelligence isn't available right now.")
            }
        }
        return .unavailable("Apple Intelligence needs iPadOS 26 or later.")
        #else
        return .unavailable("This copy of the app was built without Apple Intelligence support. Update Swift Playgrounds, then download and run the app again.")
        #endif
    }

    /// A suggester backed by the on-device model, or nil when it can't be used.
    static func makeSuggester() -> (any MetadataSuggester)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), status.isAvailable {
            return AppleIntelligenceSuggester()
        }
        #endif
        return nil
    }

    static let autoLabelOnImportKey = "appleIntelligence.autoLabelOnImport"

    /// Whether new imports are labelled automatically (on by default).
    static var autoLabelOnImport: Bool {
        UserDefaults.standard.object(forKey: autoLabelOnImportKey) as? Bool ?? true
    }
}
