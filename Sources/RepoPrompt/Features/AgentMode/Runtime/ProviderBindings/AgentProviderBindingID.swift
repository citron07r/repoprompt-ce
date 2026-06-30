import Foundation

enum AgentProviderBindingID: String, CaseIterable, Hashable {
    case codex
    case claude
    case openCode
    case cursor
    case droid
    case junie
    case pi

    var displayName: String {
        switch self {
        case .codex:
            "Codex CLI"
        case .claude:
            "Claude Code"
        case .openCode:
            "OpenCode"
        case .cursor:
            "Cursor CLI"
        case .droid:
            "Droid CLI"
        case .junie:
            "Junie CLI"
        case .pi:
            "Pi CLI"
        }
    }
}

extension AgentProviderKind {
    var providerBindingID: AgentProviderBindingID {
        switch self {
        case .codexExec:
            .codex
        case .claudeCode, .claudeCodeGLM, .kimiCode, .customClaudeCompatible:
            .claude
        case .openCode:
            .openCode
        case .cursor:
            .cursor
        case .droid:
            .droid
        case .junie:
            .junie
        case .pi:
            .pi
        }
    }
}
