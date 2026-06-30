import Foundation
@testable import RepoPrompt
import XCTest

/// Regression coverage for the Junie provider integration seams: selectable-agent
/// enumeration and runtime permission/session-mode propagation.
final class JunieProviderIntegrationTests: XCTestCase {
    func testSelectableAgentsIncludesJunieWhenAvailable() {
        let agents = AgentModelCatalog.selectableAgents(
            availability: AgentModelCatalog.AvailabilityContext(junieAvailable: true)
        )
        XCTAssertTrue(agents.contains(.junie))
    }

    func testSelectableAgentsExcludesJunieWhenUnavailable() {
        let agents = AgentModelCatalog.selectableAgents(
            availability: AgentModelCatalog.AvailabilityContext(junieAvailable: false)
        )
        XCTAssertFalse(agents.contains(.junie))
    }

    func testJunieIsListedAsSupportedCLIProvider() {
        XCTAssertTrue(AgentModelCatalog.supportedCLIProviderAgents.contains(.junie))
    }

    func testJunieFullAccessOverridePropagatesFullAccessSessionMode() {
        let store = makeSnapshotStore()
        let binding = store.runtimePermission(
            for: .junie,
            profile: .providerOverride(.junie(.fullAccess))
        )
        XCTAssertEqual(binding.acpSessionModeID, JunieAgentConfig.managedFullAccessSessionModeID)
        XCTAssertTrue(binding.acceptsPendingACPApprovalWhenActivated)
    }

    func testJunieManagedDefaultOverridePropagatesManagedSessionMode() {
        let store = makeSnapshotStore()
        let binding = store.runtimePermission(
            for: .junie,
            profile: .providerOverride(.junie(.managedDefault))
        )
        XCTAssertEqual(binding.acpSessionModeID, JunieAgentConfig.managedSessionModeID)
        XCTAssertFalse(binding.acceptsPendingACPApprovalWhenActivated)
    }

    func testJunieRuntimeKindAndIdentity() {
        XCTAssertEqual(AgentProviderKind.junie.runtimeKind, "junie_acp")
        XCTAssertEqual(AgentProviderKind.junie.commandName, "junie")
        XCTAssertEqual(AgentProviderKind.junie.acpProviderID, .junie)
        XCTAssertEqual(MCPClientIdentity.canonicalFamilyID("junie"), "junie")
    }

    private func makeSnapshotStore() -> AgentProviderPreferenceSnapshotStore {
        let suiteName = "JunieProviderIntegrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return AgentProviderPreferenceSnapshotStore(defaults: defaults)
    }
}
