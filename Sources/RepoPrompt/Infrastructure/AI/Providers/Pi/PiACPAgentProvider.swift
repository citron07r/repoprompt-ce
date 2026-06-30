import Foundation

struct PiACPAgentProvider: ACPAgentProvider {
    private let config: PiAgentConfig
    private let repoPromptMCPConfiguration: RepoPromptMCPServerConfiguration
    private let launchResolver: PiACPLaunchResolver

    #if DEBUG
        var test_config: PiAgentConfig {
            config
        }
    #endif

    init(
        config: PiAgentConfig,
        repoPromptMCPConfiguration: RepoPromptMCPServerConfiguration = .repoPrompt,
        launchResolver: PiACPLaunchResolver = PiACPLaunchResolver()
    ) {
        self.config = config
        self.repoPromptMCPConfiguration = repoPromptMCPConfiguration
        self.launchResolver = launchResolver
    }

    var providerID: ACPProviderID {
        .pi
    }

    func support(for _: ACPRunRequest) async throws -> ACPSupportResult {
        try await launchResolver.probeSupport(for: config)
    }

    func makeLaunchConfiguration(for request: ACPRunRequest) throws -> ACPLaunchConfiguration {
        let workingDirectory = standardizedWorkingDirectory(from: request.workspacePath)
        let resolvedLaunch = try launchResolver.resolvedLaunch(for: config)

        if config.includeRepoPromptMCPServer {
            try repoPromptMCPConfiguration.validateACPLaunchCommand(
                workingDirectory: workingDirectory
            )
        }

        return ACPLaunchConfiguration(
            providerID: providerID,
            command: resolvedLaunch.command,
            arguments: resolvedLaunch.arguments,
            environment: [:],
            workingDirectory: workingDirectory,
            additionalPathHints: resolvedLaunch.additionalPathHints,
            enableDebugLogging: config.enableDebugLogging,
            expectedExecutableIdentity: resolvedLaunch.executableIdentity
        )
    }

    func makeSessionConfiguration(
        for request: ACPRunRequest,
        mcpServer _: RepoPromptMCPServerConfiguration
    ) throws -> ACPSessionConfiguration {
        let mode: ACPSessionConfiguration.Mode = if let resume = request.resumeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
                                                    !resume.isEmpty
        {
            .load(existingSessionID: resume)
        } else {
            .new
        }

        return ACPSessionConfiguration(
            mode: mode,
            workingDirectory: standardizedWorkingDirectory(from: request.workspacePath),
            mcpServers: config.includeRepoPromptMCPServer ? [repoPromptMCPConfiguration] : []
        )
    }

    func buildPromptBlocks(
        for message: AgentMessage,
        request: ACPRunRequest
    ) throws -> [[String: Any]] {
        let isFollowUp = request.resumeSessionID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let systemPrompt = message.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let userMessage = message.userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String = if isFollowUp || systemPrompt.isEmpty {
            userMessage.isEmpty ? message.userMessage : userMessage
        } else if userMessage.isEmpty {
            systemPrompt
        } else {
            "\(systemPrompt)\n\n\(userMessage)"
        }

        return try ACPPromptContentBuilder.blocks(
            text: text,
            attachments: request.attachments
        )
    }

    func normalizeSessionUpdate(
        _ payload: [String: Any],
        sessionID _: String
    ) -> [NormalizedAgentRuntimeEvent] {
        PiACPEventNormalizer.normalize(payload)
    }

    func preferredAuthMethodID(context _: ACPAuthenticationContext) -> String? {
        // Pi is configured separately for its own model providers/API keys
        // (e.g. `pi-acp --terminal-login`); there is no single env token to gate on.
        nil
    }

    func normalizeError(_ error: Error) -> Error {
        if error is AIProviderError {
            return error
        }
        if let runnerError = error as? CLIProcessRunnerError,
           case .commandNotFound = runnerError
        {
            return AIProviderError.invalidConfiguration(detail: "Pi ACP adapter not found. Install it with `npm install -g pi-acp` and ensure `pi-acp` is available on PATH.")
        }
        if error is PiACPLaunchResolutionError || error is ExecutableFileIdentityError {
            return AIProviderError.invalidConfiguration(detail: error.localizedDescription)
        }
        if (error as NSError).domain == NSCocoaErrorDomain {
            return AIProviderError.invalidConfiguration(detail: "Unable to prepare Pi ACP session: \(error.localizedDescription)")
        }
        return AIProviderError.apiError(source: error)
    }

    private func standardizedWorkingDirectory(from workspacePath: String?) -> String {
        let cwd = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cwd?.isEmpty == false ? cwd : nil)
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            ?? FileManager.default.temporaryDirectory.path
    }
}
