import Foundation

/// Configuration for the Junie ACP agent provider.
///
/// Junie (JetBrains) speaks ACP natively via `junie --acp true`. RepoPrompt MCP
/// tools are injected through the ACP session configuration; no persistent config
/// files or environment overlays are required.
struct JunieAgentConfig {
    enum ToolProfile: Equatable {
        case agentMode
        case headless
        case noTools

        var sessionModeID: String {
            switch self {
            case .agentMode:
                JunieAgentConfig.managedSessionModeID
            case .headless:
                JunieAgentConfig.managedHeadlessSessionModeID
            case .noTools:
                JunieAgentConfig.managedNoToolsSessionModeID
            }
        }
    }

    /// RepoPrompt-managed Junie mode for interactive Agent Mode. Keeps bash available.
    static let managedSessionModeID = "repoprompt_acp"
    /// RepoPrompt-managed Junie mode that disables approval prompts for the managed tool surface.
    static let managedFullAccessSessionModeID = "repoprompt_acp_full_access"
    /// RepoPrompt-managed Junie mode for discovery/delegate headless paths. Denies native tools while preserving injected RepoPrompt MCP.
    static let managedHeadlessSessionModeID = "repoprompt_headless"
    /// RepoPrompt-managed Junie mode for chat/Oracle prompt-only paths. Exposes no tools.
    static let managedNoToolsSessionModeID = "repoprompt_no_tools"

    let commandName: String
    let additionalPathHints: [String]
    let modelString: String?
    let enableDebugLogging: Bool
    /// Controls whether the RepoPrompt MCP server is included in the ACP session configuration.
    let includeRepoPromptMCPServer: Bool
    let toolProfile: ToolProfile

    var sessionModeID: String {
        toolProfile.sessionModeID
    }

    init(
        commandName: String = "junie",
        additionalPathHints: [String] = CLIPathHints.junie,
        modelString: String? = nil,
        enableDebugLogging: Bool = false,
        includeRepoPromptMCPServer: Bool = true,
        toolProfile: ToolProfile = .headless
    ) {
        self.commandName = commandName
        self.additionalPathHints = additionalPathHints
        self.modelString = modelString
        self.enableDebugLogging = enableDebugLogging
        self.includeRepoPromptMCPServer = includeRepoPromptMCPServer
        self.toolProfile = toolProfile
    }
}
