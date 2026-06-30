import Foundation
@testable import RepoPrompt
import XCTest

/// Regression coverage for the Pi provider integration seams: selectable-agent
/// enumeration and runtime permission/session-mode propagation.
final class PiProviderIntegrationTests: XCTestCase {
    func testSelectableAgentsIncludesPiWhenAvailable() {
        let agents = AgentModelCatalog.selectableAgents(
            availability: AgentModelCatalog.AvailabilityContext(piAvailable: true)
        )
        XCTAssertTrue(agents.contains(.pi))
    }

    func testSelectableAgentsExcludesPiWhenUnavailable() {
        let agents = AgentModelCatalog.selectableAgents(
            availability: AgentModelCatalog.AvailabilityContext(piAvailable: false)
        )
        XCTAssertFalse(agents.contains(.pi))
    }

    func testPiIsListedAsSupportedCLIProvider() {
        XCTAssertTrue(AgentModelCatalog.supportedCLIProviderAgents.contains(.pi))
    }

    func testPiFullAccessOverridePropagatesFullAccessSessionMode() {
        let store = makeSnapshotStore()
        let binding = store.runtimePermission(
            for: .pi,
            profile: .providerOverride(.pi(.fullAccess))
        )
        XCTAssertEqual(binding.acpSessionModeID, PiAgentConfig.managedFullAccessSessionModeID)
        XCTAssertTrue(binding.acceptsPendingACPApprovalWhenActivated)
    }

    func testPiManagedDefaultOverridePropagatesManagedSessionMode() {
        let store = makeSnapshotStore()
        let binding = store.runtimePermission(
            for: .pi,
            profile: .providerOverride(.pi(.managedDefault))
        )
        XCTAssertEqual(binding.acpSessionModeID, PiAgentConfig.managedSessionModeID)
        XCTAssertFalse(binding.acceptsPendingACPApprovalWhenActivated)
    }

    func testPiRuntimeKindAndIdentity() {
        XCTAssertEqual(AgentProviderKind.pi.runtimeKind, "pi_acp")
        XCTAssertEqual(AgentProviderKind.pi.commandName, "pi-acp")
        XCTAssertEqual(AgentProviderKind.pi.acpProviderID, .pi)
        XCTAssertEqual(MCPClientIdentity.canonicalFamilyID("pi"), "pi")
        XCTAssertEqual(MCPClientIdentity.canonicalFamilyID("pi-acp"), "pi")
    }

    private func makeSnapshotStore() -> AgentProviderPreferenceSnapshotStore {
        let suiteName = "PiProviderIntegrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return AgentProviderPreferenceSnapshotStore(defaults: defaults)
    }
}
