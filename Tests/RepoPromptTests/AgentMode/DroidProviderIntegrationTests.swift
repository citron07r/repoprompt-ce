import Foundation
@testable import RepoPrompt
import XCTest

/// Regression coverage for the Droid provider integration seams that the initial
/// patch broke: selectable-agent enumeration (CR-02) and runtime permission/session
/// mode propagation (CR-03).
final class DroidProviderIntegrationTests: XCTestCase {
    // MARK: - CR-02: selectable agents

    func testSelectableAgentsIncludesDroidWhenAvailable() {
        let agents = AgentModelCatalog.selectableAgents(
            availability: AgentModelCatalog.AvailabilityContext(droidAvailable: true)
        )
        XCTAssertTrue(agents.contains(.droid))
    }

    func testSelectableAgentsExcludesDroidWhenUnavailable() {
        let agents = AgentModelCatalog.selectableAgents(
            availability: AgentModelCatalog.AvailabilityContext(droidAvailable: false)
        )
        XCTAssertFalse(agents.contains(.droid))
    }

    func testDroidIsListedAsSupportedCLIProvider() {
        XCTAssertTrue(AgentModelCatalog.supportedCLIProviderAgents.contains(.droid))
    }

    // MARK: - CR-03: runtime permission / session mode propagation

    func testDroidFullAccessOverridePropagatesFullAccessSessionMode() {
        let store = makeSnapshotStore()
        let binding = store.runtimePermission(
            for: .droid,
            profile: .providerOverride(.droid(.fullAccess))
        )
        XCTAssertEqual(binding.acpSessionModeID, DroidAgentConfig.managedFullAccessSessionModeID)
        XCTAssertTrue(binding.acceptsPendingACPApprovalWhenActivated)
    }

    func testDroidManagedDefaultOverridePropagatesManagedSessionMode() {
        let store = makeSnapshotStore()
        let binding = store.runtimePermission(
            for: .droid,
            profile: .providerOverride(.droid(.managedDefault))
        )
        XCTAssertEqual(binding.acpSessionModeID, DroidAgentConfig.managedSessionModeID)
        XCTAssertFalse(binding.acceptsPendingACPApprovalWhenActivated)
    }

    func testDroidUserConfiguredFullAccessPropagatesFullAccessSessionMode() {
        let defaults = makeIsolatedDefaults()
        DroidAgentToolPreferences.setPermissionLevel(.fullAccess, defaults: defaults, secureStore: nil)

        let store = AgentProviderPreferenceSnapshotStore(defaults: defaults)
        let binding = store.runtimePermission(for: .droid, profile: .userConfigured)

        XCTAssertEqual(binding.acpSessionModeID, DroidAgentConfig.managedFullAccessSessionModeID)
    }

    // MARK: - Helpers

    private func makeSnapshotStore() -> AgentProviderPreferenceSnapshotStore {
        AgentProviderPreferenceSnapshotStore(defaults: makeIsolatedDefaults())
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "DroidProviderIntegrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
