import Foundation

/// Event normalizer for Junie ACP sessions.
///
/// Delegates to the generic ACP default session update normalizer. Custom
/// Junie-specific event classification can be added here when needed.
enum JunieACPEventNormalizer {
    static func normalize(_ payload: [String: Any]) -> [NormalizedAgentRuntimeEvent] {
        ACPDefaultSessionUpdateNormalizer.normalize(payload, providerID: .junie)
    }
}
