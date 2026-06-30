import Foundation

/// Event normalizer for Pi ACP sessions.
///
/// Delegates to the generic ACP default session update normalizer. Custom
/// Pi-specific event classification can be added here when needed.
enum PiACPEventNormalizer {
    static func normalize(_ payload: [String: Any]) -> [NormalizedAgentRuntimeEvent] {
        ACPDefaultSessionUpdateNormalizer.normalize(payload, providerID: .pi)
    }
}
