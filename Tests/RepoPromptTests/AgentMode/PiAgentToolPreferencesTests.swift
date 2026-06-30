import Foundation
@testable import RepoPrompt
import XCTest

final class PiAgentToolPreferencesTests: XCTestCase {
    func testPermissionLevelSessionModeIDs() {
        XCTAssertEqual(
            PiAgentToolPreferences.PermissionLevel.managedDefault.sessionModeID,
            PiAgentConfig.managedSessionModeID
        )
        XCTAssertEqual(
            PiAgentToolPreferences.PermissionLevel.fullAccess.sessionModeID,
            PiAgentConfig.managedFullAccessSessionModeID
        )
    }

    func testPermissionLevelAcceptsPendingApprovalFlag() {
        XCTAssertFalse(PiAgentToolPreferences.PermissionLevel.managedDefault.acceptsPendingApprovalWhenActivated)
        XCTAssertTrue(PiAgentToolPreferences.PermissionLevel.fullAccess.acceptsPendingApprovalWhenActivated)
    }

    func testFromSessionModeIDReturnsCorrectLevel() {
        XCTAssertEqual(
            PiAgentToolPreferences.PermissionLevel.from(sessionModeID: PiAgentConfig.managedFullAccessSessionModeID),
            .fullAccess
        )
        XCTAssertEqual(
            PiAgentToolPreferences.PermissionLevel.from(sessionModeID: "unknown_mode"),
            .managedDefault
        )
    }

    func testSetPermissionLevelPersistsAndReturnsCorrectValue() {
        let defaults = makeIsolatedDefaults()
        PiAgentToolPreferences.setPermissionLevel(.fullAccess, defaults: defaults, secureStore: nil)
        XCTAssertEqual(PiAgentToolPreferences.permissionLevel(defaults: defaults, secureStore: nil), .fullAccess)
        PiAgentToolPreferences.setPermissionLevel(.managedDefault, defaults: defaults, secureStore: nil)
        XCTAssertEqual(PiAgentToolPreferences.permissionLevel(defaults: defaults, secureStore: nil), .managedDefault)
    }

    func testSecurePiPermissionDocumentRoundTrip() {
        let document = SecurePiPermissionDocument()
        XCTAssertEqual(document.permissionLevel(), .managedDefault)
        XCTAssertEqual(document.sessionModeID(), PiAgentConfig.managedSessionModeID)

        var fullAccess = SecurePiPermissionDocument()
        fullAccess.permissionLevelRaw = PiAgentToolPreferences.PermissionLevel.fullAccess.rawValue
        XCTAssertEqual(fullAccess.permissionLevel(), .fullAccess)
        XCTAssertEqual(fullAccess.sessionModeID(), PiAgentConfig.managedFullAccessSessionModeID)
    }

    func testDefaultConfigValues() {
        let config = PiAgentConfig()
        XCTAssertEqual(config.commandName, "pi-acp")
        XCTAssertEqual(config.additionalPathHints, CLIPathHints.pi)
        XCTAssertTrue(config.includeRepoPromptMCPServer)
        XCTAssertEqual(config.toolProfile, .headless)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "PiAgentToolPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
