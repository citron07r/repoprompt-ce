import Foundation
@testable import RepoPrompt
import XCTest

final class JunieAgentToolPreferencesTests: XCTestCase {
    func testPermissionLevelSessionModeIDs() {
        XCTAssertEqual(
            JunieAgentToolPreferences.PermissionLevel.managedDefault.sessionModeID,
            JunieAgentConfig.managedSessionModeID
        )
        XCTAssertEqual(
            JunieAgentToolPreferences.PermissionLevel.fullAccess.sessionModeID,
            JunieAgentConfig.managedFullAccessSessionModeID
        )
    }

    func testPermissionLevelAcceptsPendingApprovalFlag() {
        XCTAssertFalse(JunieAgentToolPreferences.PermissionLevel.managedDefault.acceptsPendingApprovalWhenActivated)
        XCTAssertTrue(JunieAgentToolPreferences.PermissionLevel.fullAccess.acceptsPendingApprovalWhenActivated)
    }

    func testFromSessionModeIDReturnsCorrectLevel() {
        XCTAssertEqual(
            JunieAgentToolPreferences.PermissionLevel.from(sessionModeID: JunieAgentConfig.managedFullAccessSessionModeID),
            .fullAccess
        )
        XCTAssertEqual(
            JunieAgentToolPreferences.PermissionLevel.from(sessionModeID: "unknown_mode"),
            .managedDefault
        )
    }

    func testSetPermissionLevelPersistsAndReturnsCorrectValue() {
        let defaults = makeIsolatedDefaults()
        JunieAgentToolPreferences.setPermissionLevel(.fullAccess, defaults: defaults, secureStore: nil)
        XCTAssertEqual(JunieAgentToolPreferences.permissionLevel(defaults: defaults, secureStore: nil), .fullAccess)
        JunieAgentToolPreferences.setPermissionLevel(.managedDefault, defaults: defaults, secureStore: nil)
        XCTAssertEqual(JunieAgentToolPreferences.permissionLevel(defaults: defaults, secureStore: nil), .managedDefault)
    }

    func testSecureJuniePermissionDocumentRoundTrip() {
        let document = SecureJuniePermissionDocument()
        XCTAssertEqual(document.permissionLevel(), .managedDefault)
        XCTAssertEqual(document.sessionModeID(), JunieAgentConfig.managedSessionModeID)

        var fullAccess = SecureJuniePermissionDocument()
        fullAccess.permissionLevelRaw = JunieAgentToolPreferences.PermissionLevel.fullAccess.rawValue
        XCTAssertEqual(fullAccess.permissionLevel(), .fullAccess)
        XCTAssertEqual(fullAccess.sessionModeID(), JunieAgentConfig.managedFullAccessSessionModeID)
    }

    func testDefaultConfigValues() {
        let config = JunieAgentConfig()
        XCTAssertEqual(config.commandName, "junie")
        XCTAssertEqual(config.additionalPathHints, CLIPathHints.junie)
        XCTAssertTrue(config.includeRepoPromptMCPServer)
        XCTAssertEqual(config.toolProfile, .headless)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "JunieAgentToolPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
