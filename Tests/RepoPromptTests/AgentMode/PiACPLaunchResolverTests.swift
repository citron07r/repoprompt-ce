import Foundation
@testable import RepoPrompt
import XCTest

final class PiACPLaunchResolverTests: XCTestCase {
    func testMakeLaunchConfigurationResolvesExplicitPathWithoutPriorProbe() throws {
        let directory = try makeTemporaryDirectory()
        let executable = try makeExecutable(in: directory)
        let resolver = PiACPLaunchResolver()
        let provider = PiACPAgentProvider(
            config: PiAgentConfig(
                commandName: executable.path,
                additionalPathHints: [],
                includeRepoPromptMCPServer: false
            ),
            launchResolver: resolver
        )

        let launch = try provider.makeLaunchConfiguration(for: makeRunRequest(workspacePath: directory.path))

        XCTAssertEqual(launch.command, try canonicalExecutablePath(executable))
        XCTAssertEqual(launch.arguments, [])
        XCTAssertEqual(launch.expectedExecutableIdentity?.canonicalPath, launch.command)
    }

    func testBareCommandUsesCapturedEnvironmentAndCachesCanonicalPathForSpawn() async throws {
        let directory = try makeTemporaryDirectory()
        let probePathRecord = directory.appendingPathComponent("probe-path")
        let executable = try makeExecutable(in: directory, marker: probePathRecord)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = directory.path
        environment["SHELL"] = "/bin/false"
        let capturedEnvironment = environment
        let resolver = PiACPLaunchResolver(environmentProvider: { _ in capturedEnvironment })
        let config = PiAgentConfig(
            commandName: "pi-acp",
            additionalPathHints: [],
            includeRepoPromptMCPServer: false
        )

        let support = try await resolver.probeSupport(for: config)
        let launch = try resolver.resolvedLaunch(for: config)
        let probedPath = try String(contentsOf: probePathRecord, encoding: .utf8)

        XCTAssertEqual(support, .supported)
        XCTAssertEqual(launch.command, try canonicalExecutablePath(executable))
        XCTAssertEqual(probedPath, launch.command)
    }

    /// Pi's adapter is the ACP bridge itself, so a clean `--help` exit is the support
    /// signal even when the output does not contain the literal "acp" token.
    func testProbeSucceedsWithoutACPSubstringInHelpOutput() async throws {
        let directory = try makeTemporaryDirectory()
        let executable = try makeExecutable(in: directory, output: "pi adapter usage, no marker")
        let support = try await PiACPLaunchResolver().probeSupport(
            for: PiAgentConfig(commandName: executable.path, additionalPathHints: [])
        )
        XCTAssertEqual(support, .supported)
    }

    func testPiHomeBinHintDoesNotLeakIntoNativeDefaultsOrOtherProviders() {
        XCTAssertEqual(CLILaunchProfiles.piProviderSpecificPaths, [])
        XCTAssertFalse(CLILaunchProfiles.claudeCode.supplementalSearchPaths.contains(where: { $0.contains("pi-acp") }))
        XCTAssertFalse(CLILaunchProfiles.codex.supplementalSearchPaths.contains(where: { $0.contains("pi-acp") }))
        XCTAssertFalse(CLILaunchProfiles.openCode.supplementalSearchPaths.contains(where: { $0.contains("pi-acp") }))
        XCTAssertFalse(CLILaunchProfiles.cursor.supplementalSearchPaths.contains(where: { $0.contains("pi-acp") }))
    }

    func testBareCommandWithoutSuccessfulPreflightFailsClosed() {
        let resolver = PiACPLaunchResolver(environmentProvider: { _ in [:] })

        XCTAssertThrowsError(
            try resolver.resolvedLaunch(
                for: PiAgentConfig(commandName: "pi-acp", additionalPathHints: [])
            )
        ) { error in
            guard case PiACPLaunchResolutionError.environmentDiscoveryRequired = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testFailedProbeDoesNotLeaveSpawnableCacheAndReplacementCanRecover() async throws {
        let directory = try makeTemporaryDirectory()
        let executable = try makeExecutable(in: directory, exitStatus: 2)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = directory.path
        environment["SHELL"] = "/bin/false"
        let capturedEnvironment = environment
        let resolver = PiACPLaunchResolver(environmentProvider: { _ in capturedEnvironment })
        let config = PiAgentConfig(commandName: "pi-acp", additionalPathHints: [])

        guard case .unsupported = try await resolver.probeSupport(for: config) else {
            return XCTFail("Expected failed support probe")
        }
        XCTAssertThrowsError(try resolver.resolvedLaunch(for: config)) { error in
            guard case PiACPLaunchResolutionError.environmentDiscoveryRequired = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        try FileManager.default.removeItem(at: executable)
        let replacement = try makeExecutable(in: directory)
        let replacementSupport = try await resolver.probeSupport(for: config)
        XCTAssertEqual(replacementSupport, .supported)
        XCTAssertEqual(
            try resolver.resolvedLaunch(for: config).command,
            try canonicalExecutablePath(replacement)
        )
    }

    private func makeRunRequest(workspacePath: String) -> ACPRunRequest {
        ACPRunRequest(
            agentKind: .pi,
            modelString: nil,
            workspacePath: workspacePath,
            resumeSessionID: nil,
            attachments: [],
            taskLabelKind: nil
        )
    }

    private func canonicalExecutablePath(_ url: URL) throws -> String {
        try XCTUnwrap(FileSystemService.realpathString(url.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiACPLaunchResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    @discardableResult
    private func makeExecutable(
        in directory: URL,
        marker: URL? = nil,
        output: String = "pi acp adapter",
        exitStatus: Int32 = 0,
        sleepSeconds: Int? = nil
    ) throws -> URL {
        let executable = directory.appendingPathComponent("pi-acp")
        var lines = ["#!/bin/sh"]
        if let marker {
            lines.append("printf '%s' \"$0\" > '\(marker.path)'")
        }
        if let sleepSeconds {
            lines.append("exec /bin/sleep \(sleepSeconds)")
        }
        lines.append("printf '%s\\n' '\(output)'")
        lines.append("exit \(exitStatus)")
        try lines.joined(separator: "\n").write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }
}
