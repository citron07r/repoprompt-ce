import Foundation
@testable import RepoPrompt
import XCTest

final class JunieACPLaunchResolverTests: XCTestCase {
    func testMakeLaunchConfigurationResolvesExplicitPathWithoutPriorProbe() throws {
        let directory = try makeTemporaryDirectory()
        let executable = try makeExecutable(in: directory)
        let resolver = JunieACPLaunchResolver()
        let provider = JunieACPAgentProvider(
            config: JunieAgentConfig(
                commandName: executable.path,
                additionalPathHints: [],
                includeRepoPromptMCPServer: false
            ),
            launchResolver: resolver
        )

        let launch = try provider.makeLaunchConfiguration(for: makeRunRequest(workspacePath: directory.path))

        XCTAssertEqual(launch.command, try canonicalExecutablePath(executable))
        XCTAssertEqual(launch.arguments, ["--acp", "true"])
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
        let resolver = JunieACPLaunchResolver(environmentProvider: { _ in capturedEnvironment })
        let config = JunieAgentConfig(
            commandName: "junie",
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

    func testJunieHomeBinHintDoesNotLeakIntoNativeDefaultsOrOtherProviders() {
        XCTAssertEqual(CLILaunchProfiles.junieProviderSpecificPaths, [])
        XCTAssertFalse(CLILaunchProfiles.claudeCode.supplementalSearchPaths.contains(where: { $0.contains("junie") }))
        XCTAssertFalse(CLILaunchProfiles.codex.supplementalSearchPaths.contains(where: { $0.contains("junie") }))
        XCTAssertFalse(CLILaunchProfiles.openCode.supplementalSearchPaths.contains(where: { $0.contains("junie") }))
        XCTAssertFalse(CLILaunchProfiles.cursor.supplementalSearchPaths.contains(where: { $0.contains("junie") }))
    }

    func testBareCommandWithoutSuccessfulPreflightFailsClosed() {
        let resolver = JunieACPLaunchResolver(environmentProvider: { _ in [:] })

        XCTAssertThrowsError(
            try resolver.resolvedLaunch(
                for: JunieAgentConfig(commandName: "junie", additionalPathHints: [])
            )
        ) { error in
            guard case JunieACPLaunchResolutionError.environmentDiscoveryRequired = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testUnsupportedWhenHelpDoesNotAdvertiseACP() async throws {
        let directory = try makeTemporaryDirectory()
        let executable = try makeExecutable(in: directory, output: "Junie usage without the marker")
        let support = try await JunieACPLaunchResolver().probeSupport(
            for: JunieAgentConfig(commandName: executable.path, additionalPathHints: [])
        )
        guard case .unsupported = support else {
            return XCTFail("Expected unsupported when ACP is not advertised")
        }
    }

    func testFailedProbeDoesNotLeaveSpawnableCacheAndReplacementCanRecover() async throws {
        let directory = try makeTemporaryDirectory()
        let executable = try makeExecutable(in: directory, exitStatus: 2)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = directory.path
        environment["SHELL"] = "/bin/false"
        let capturedEnvironment = environment
        let resolver = JunieACPLaunchResolver(environmentProvider: { _ in capturedEnvironment })
        let config = JunieAgentConfig(commandName: "junie", additionalPathHints: [])

        guard case .unsupported = try await resolver.probeSupport(for: config) else {
            return XCTFail("Expected failed support probe")
        }
        XCTAssertThrowsError(try resolver.resolvedLaunch(for: config)) { error in
            guard case JunieACPLaunchResolutionError.environmentDiscoveryRequired = error else {
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
            agentKind: .junie,
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
            .appendingPathComponent("JunieACPLaunchResolverTests-\(UUID().uuidString)", isDirectory: true)
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
        output: String = "Junie ACP support",
        exitStatus: Int32 = 0,
        sleepSeconds: Int? = nil
    ) throws -> URL {
        let executable = directory.appendingPathComponent("junie")
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
