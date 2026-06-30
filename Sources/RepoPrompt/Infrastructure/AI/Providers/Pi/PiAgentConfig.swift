import Foundation

/// Configuration for the Pi ACP agent provider.
///
/// The `pi` coding agent does not speak ACP natively; integration goes through
/// the `pi-acp` adapter binary, which speaks ACP over stdio and internally
/// spawns `pi --mode rpc`. RepoPrompt MCP tools are injected through the ACP
/// session configuration; no persistent config files are required.
struct PiAgentConfig {
    enum ToolProfile: Equatable {
        case agentMode
        case headless
        case noTools

        var sessionModeID: String {
            switch self {
            case .agentMode:
                PiAgentConfig.managedSessionModeID
            case .headless:
                PiAgentConfig.managedHeadlessSessionModeID
            case .noTools:
                PiAgentConfig.managedNoToolsSessionModeID
            }
        }
    }

    /// RepoPrompt-managed Pi mode for interactive Agent Mode. Keeps bash available.
    static let managedSessionModeID = "repoprompt_acp"
    /// RepoPrompt-managed Pi mode that disables approval prompts for the managed tool surface.
    static let managedFullAccessSessionModeID = "repoprompt_acp_full_access"
    /// RepoPrompt-managed Pi mode for discovery/delegate headless paths. Denies native tools while preserving injected RepoPrompt MCP.
    static let managedHeadlessSessionModeID = "repoprompt_headless"
    /// RepoPrompt-managed Pi mode for chat/Oracle prompt-only paths. Exposes no tools.
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
        commandName: String = "pi-acp",
        additionalPathHints: [String] = CLIPathHints.pi,
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
