import Foundation
import FoundationModels

/// Apple Intelligence's on-device language model: free, offline, and nothing leaves the
/// phone. It is small, so callers hand it short, pre-computed context and keep a plain
/// fallback for when it is off, still downloading, or declines.
enum OnDeviceModel {
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    /// Why it can't run, in words for the user; nil when it can.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings for written summaries."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading; written summaries will appear once it's ready."
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable:
            return "Apple Intelligence isn't available right now."
        }
    }
}
