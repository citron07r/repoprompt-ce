import Foundation

struct JunieACPResolvedLaunch: Equatable {
    let command: String
    let arguments: [String]
    let additionalPathHints: [String]
    let executableIdentity: ExecutableFileIdentity
}

enum JunieACPLaunchResolutionError: Error, Equatable, LocalizedError {
    case missingConfiguredCommand
    case exactPathNotFound(String)
    case environmentDiscoveryRequired(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguredCommand:
            "Junie ACP launch requires a `junie` command or executable path."
        case let .exactPathNotFound(command):
            "Junie CLI was not found as a valid executable regular file for `\(command)`. Install Junie or configure its absolute path."
        case let .environmentDiscoveryRequired(command):
            "Junie CLI path discovery has not completed for `\(command)`. Run the Junie ACP support preflight or configure an absolute executable path."
        }
    }
}

final class JunieACPLaunchResolver: @unchecked Sendable {
    typealias EnvironmentProvider = @Sendable (_ enableDebugLogging: Bool) async -> [String: String]

    private static let launchArguments = ["--acp", "true"]
    private static let helpArguments = ["--help"]

    private let environmentProvider: EnvironmentProvider
    private let probeMutex = AsyncMutex()
    private let lock = NSLock()
    private var cachedLaunchByKey: [String: JunieACPResolvedLaunch] = [:]

    init(
        environmentProvider: @escaping EnvironmentProvider = { enableDebugLogging in
            let result = await ProcessEnvironmentBuilder.build(
                ProcessEnvironmentRequest(
                    purpose: .acpAgent(providerID: ACPProviderID.junie.rawValue),
                    enableDebugLogging: enableDebugLogging
                )
            )
            return result.environment
        }
    ) {
        self.environmentProvider = environmentProvider
    }

    func resolvedLaunch(for config: JunieAgentConfig) throws -> JunieACPResolvedLaunch {
        let key = cacheKey(for: config)
        if let cached = cachedLaunch(forKey: key) {
            do {
                try cached.executableIdentity.validateForTrustedPathLaunch(atPath: cached.command)
                return cached
            } catch {
                invalidate(key: key)
                throw error
            }
        }

        let launch = try resolveExplicitLaunch(for: config)
        cache(launch, key: key)
        return launch
    }

    func probeSupport(for config: JunieAgentConfig) async throws -> ACPSupportResult {
        try await probeMutex.withLock { [self] in
            try await probeSupportSerially(for: config)
        }
    }

    private func probeSupportSerially(for config: JunieAgentConfig) async throws -> ACPSupportResult {
        let key = cacheKey(for: config)
        invalidate(key: key)
        do {
            let launch = try await resolveLaunchForProbe(for: config)
            let processConfig = CLIProcessConfiguration(
                command: launch.command,
                additionalPaths: [],
                enableDebugLogging: config.enableDebugLogging
            )
            let result = try await CLIProcessRunner(config: processConfig).run(
                args: Self.helpArguments,
                stdin: nil,
                outputMode: .none,
                timeout: 10,
                cancelChildOnTaskCancellation: true
            )
            guard result.status == 0 else {
                return .unsupported(
                    reason: "Junie ACP preflight failed: `junie --help` exited with status \(result.status)."
                )
            }

            let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            guard "\(stdout)\n\(stderr)".localizedCaseInsensitiveContains("acp") else {
                return .unsupported(reason: "Installed Junie CLI does not advertise ACP support.")
            }

            try launch.executableIdentity.validateForTrustedPathLaunch(atPath: launch.command)
            cache(launch, key: key)
            return .supported
        } catch is CancellationError {
            invalidate(key: key)
            throw CancellationError()
        } catch {
            invalidate(key: key)
            return .unsupported(reason: error.localizedDescription)
        }
    }

    private func resolveLaunchForProbe(for config: JunieAgentConfig) async throws -> JunieACPResolvedLaunch {
        let configuredCommand = try validatedConfiguredCommand(config)
        let environment = await environmentProvider(config.enableDebugLogging)
        try Task.checkCancellation()
        if configuredCommand.contains("/") {
            return try resolveExplicitLaunch(for: config, environment: environment)
        }

        let effectiveHints = Self.effectiveSearchPaths(providerSpecificPaths: config.additionalPathHints)
        let resolved = CommandPathResolver.resolve(
            configuredCommand,
            environment: environment,
            additionalPaths: effectiveHints,
            preferredBasenames: [configuredCommand]
        )
        return try validatedLaunch(
            entryPath: resolved,
            configuredCommand: configuredCommand,
            additionalPathHints: effectiveHints
        )
    }

    private func resolveExplicitLaunch(
        for config: JunieAgentConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> JunieACPResolvedLaunch {
        let configuredCommand = try validatedConfiguredCommand(config)
        guard configuredCommand.contains("/") else {
            throw JunieACPLaunchResolutionError.environmentDiscoveryRequired(configuredCommand)
        }
        let effectiveHints = Self.effectiveSearchPaths(providerSpecificPaths: config.additionalPathHints)
        return try validatedLaunch(
            entryPath: CommandPathResolver.expandPath(configuredCommand, environment: environment),
            configuredCommand: configuredCommand,
            additionalPathHints: effectiveHints
        )
    }

    private func validatedConfiguredCommand(_ config: JunieAgentConfig) throws -> String {
        let command = config.commandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw JunieACPLaunchResolutionError.missingConfiguredCommand
        }
        return command
    }

    private func validatedLaunch(
        entryPath: String,
        configuredCommand: String,
        additionalPathHints: [String]
    ) throws -> JunieACPResolvedLaunch {
        guard entryPath.hasPrefix("/") else {
            throw JunieACPLaunchResolutionError.exactPathNotFound(configuredCommand)
        }

        let identity: ExecutableFileIdentity
        do {
            identity = try ExecutableFileIdentity.captureForTrustedPathLaunch(atPath: entryPath)
        } catch {
            throw JunieACPLaunchResolutionError.exactPathNotFound(configuredCommand)
        }

        return JunieACPResolvedLaunch(
            command: identity.canonicalPath,
            arguments: Self.launchArguments,
            additionalPathHints: additionalPathHints,
            executableIdentity: identity
        )
    }

    private func cachedLaunch(forKey key: String) -> JunieACPResolvedLaunch? {
        lock.lock()
        defer { lock.unlock() }
        return cachedLaunchByKey[key]
    }

    private func cache(_ launch: JunieACPResolvedLaunch, key: String) {
        lock.lock()
        cachedLaunchByKey[key] = launch
        lock.unlock()
    }

    private func invalidate(key: String) {
        lock.lock()
        cachedLaunchByKey.removeValue(forKey: key)
        lock.unlock()
    }

    private func cacheKey(for config: JunieAgentConfig) -> String {
        ([config.commandName] + config.additionalPathHints).joined(separator: "\u{1F}")
    }

    private static func effectiveSearchPaths(providerSpecificPaths: [String]) -> [String] {
        CLILaunchProfiles.providerSpecificPathsSupplementedWithNativeDefaults(providerSpecificPaths)
    }
}
