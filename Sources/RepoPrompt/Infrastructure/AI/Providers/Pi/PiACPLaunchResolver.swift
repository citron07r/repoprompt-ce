import Foundation

struct PiACPResolvedLaunch: Equatable {
    let command: String
    let arguments: [String]
    let additionalPathHints: [String]
    let executableIdentity: ExecutableFileIdentity
}

enum PiACPLaunchResolutionError: Error, Equatable, LocalizedError {
    case missingConfiguredCommand
    case exactPathNotFound(String)
    case environmentDiscoveryRequired(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguredCommand:
            "Pi ACP launch requires a `pi-acp` command or executable path."
        case let .exactPathNotFound(command):
            "Pi ACP adapter was not found as a valid executable regular file for `\(command)`. Install `pi-acp` (npm) or configure its absolute path."
        case let .environmentDiscoveryRequired(command):
            "Pi ACP adapter path discovery has not completed for `\(command)`. Run the Pi ACP support preflight or configure an absolute executable path."
        }
    }
}

final class PiACPLaunchResolver: @unchecked Sendable {
    typealias EnvironmentProvider = @Sendable (_ enableDebugLogging: Bool) async -> [String: String]

    private static let launchArguments: [String] = []
    private static let helpArguments = ["--help"]

    private let environmentProvider: EnvironmentProvider
    private let probeMutex = AsyncMutex()
    private let lock = NSLock()
    private var cachedLaunchByKey: [String: PiACPResolvedLaunch] = [:]

    init(
        environmentProvider: @escaping EnvironmentProvider = { enableDebugLogging in
            let result = await ProcessEnvironmentBuilder.build(
                ProcessEnvironmentRequest(
                    purpose: .acpAgent(providerID: ACPProviderID.pi.rawValue),
                    enableDebugLogging: enableDebugLogging
                )
            )
            return result.environment
        }
    ) {
        self.environmentProvider = environmentProvider
    }

    func resolvedLaunch(for config: PiAgentConfig) throws -> PiACPResolvedLaunch {
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

    func probeSupport(for config: PiAgentConfig) async throws -> ACPSupportResult {
        try await probeMutex.withLock { [self] in
            try await probeSupportSerially(for: config)
        }
    }

    private func probeSupportSerially(for config: PiAgentConfig) async throws -> ACPSupportResult {
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
            // The pi-acp adapter is itself the ACP bridge; its `--help` output is not
            // guaranteed to advertise the literal "acp" token, so a clean exit is the
            // support signal (unlike Droid/Junie which gate on an "acp" substring).
            guard result.status == 0 else {
                return .unsupported(
                    reason: "Pi ACP preflight failed: `pi-acp --help` exited with status \(result.status)."
                )
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

    private func resolveLaunchForProbe(for config: PiAgentConfig) async throws -> PiACPResolvedLaunch {
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
        for config: PiAgentConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> PiACPResolvedLaunch {
        let configuredCommand = try validatedConfiguredCommand(config)
        guard configuredCommand.contains("/") else {
            throw PiACPLaunchResolutionError.environmentDiscoveryRequired(configuredCommand)
        }
        let effectiveHints = Self.effectiveSearchPaths(providerSpecificPaths: config.additionalPathHints)
        return try validatedLaunch(
            entryPath: CommandPathResolver.expandPath(configuredCommand, environment: environment),
            configuredCommand: configuredCommand,
            additionalPathHints: effectiveHints
        )
    }

    private func validatedConfiguredCommand(_ config: PiAgentConfig) throws -> String {
        let command = config.commandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw PiACPLaunchResolutionError.missingConfiguredCommand
        }
        return command
    }

    private func validatedLaunch(
        entryPath: String,
        configuredCommand: String,
        additionalPathHints: [String]
    ) throws -> PiACPResolvedLaunch {
        guard entryPath.hasPrefix("/") else {
            throw PiACPLaunchResolutionError.exactPathNotFound(configuredCommand)
        }

        let identity: ExecutableFileIdentity
        do {
            identity = try ExecutableFileIdentity.captureForTrustedPathLaunch(atPath: entryPath)
        } catch {
            throw PiACPLaunchResolutionError.exactPathNotFound(configuredCommand)
        }

        return PiACPResolvedLaunch(
            command: identity.canonicalPath,
            arguments: Self.launchArguments,
            additionalPathHints: additionalPathHints,
            executableIdentity: identity
        )
    }

    private func cachedLaunch(forKey key: String) -> PiACPResolvedLaunch? {
        lock.lock()
        defer { lock.unlock() }
        return cachedLaunchByKey[key]
    }

    private func cache(_ launch: PiACPResolvedLaunch, key: String) {
        lock.lock()
        cachedLaunchByKey[key] = launch
        lock.unlock()
    }

    private func invalidate(key: String) {
        lock.lock()
        cachedLaunchByKey.removeValue(forKey: key)
        lock.unlock()
    }

    private func cacheKey(for config: PiAgentConfig) -> String {
        ([config.commandName] + config.additionalPathHints).joined(separator: "\u{1F}")
    }

    private static func effectiveSearchPaths(providerSpecificPaths: [String]) -> [String] {
        CLILaunchProfiles.providerSpecificPathsSupplementedWithNativeDefaults(providerSpecificPaths)
    }
}
