@testable import RepoPrompt
import XCTest

final class WorkspaceSelectionAutoCodemapInvariantTests: XCTestCase {
    func testFullAndSliceMutationsPersistOnlyExplicitSelectionState() async throws {
        let root = try makeRoot(named: #function)
        defer { try? FileManager.default.removeItem(at: root) }

        let selectedA = root.appendingPathComponent("A.swift")
        let selectedB = root.appendingPathComponent("B.swift")
        try write("struct A {}", to: selectedA)
        try write("struct B {}", to: selectedB)

        let store = WorkspaceFileContextStore()
        let loaded = try await store.loadRoot(path: root.path)
        let service = WorkspaceSelectionMutationService(store: store)
        let initial = StoredSelection(
            selectedPaths: [selectedA.path],
            codemapAutoEnabled: true
        )

        let added = await service.addPaths(
            existing: initial,
            paths: [selectedB.path],
            rawPaths: [selectedB.path],
            mode: "full"
        )
        XCTAssertEqual(added.selection.selectedPaths, [selectedA.path, selectedB.path])
        XCTAssertTrue(added.selection.codemapAutoEnabled)

        let sliced = await service.mutateSlices(
            base: added.selection,
            entries: [
                WorkspaceSelectionSliceInput(
                    path: selectedA.path,
                    ranges: [LineRange(start: 1, end: 1)]
                )
            ],
            mode: .add
        )
        XCTAssertEqual(
            sliced.selection.slices[selectedA.path],
            [LineRange(start: 1, end: 1)]
        )
        await store.unloadRoot(id: loaded.id)
    }

    func testManualCodemapOnlyMutationsFailClosed() async throws {
        let root = try makeRoot(named: #function)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Selected.swift")
        try write("struct Selected {}", to: file)

        let store = WorkspaceFileContextStore()
        let loaded = try await store.loadRoot(path: root.path)
        let service = WorkspaceSelectionMutationService(store: store)
        let initial = StoredSelection(selectedPaths: [file.path], codemapAutoEnabled: true)
        let expectedMessage = "manual codemap-only selections are no longer stored."

        let built = await service.buildSelection(
            paths: [file.path],
            mode: "codemap_only",
            existing: initial
        )
        XCTAssertEqual(built.selection, initial)
        XCTAssertEqual(built.invalidPaths, [expectedMessage])

        let added = await service.addPaths(
            existing: initial,
            paths: [file.path],
            rawPaths: [file.path],
            mode: "codemap_only"
        )
        XCTAssertEqual(added.selection, initial)
        XCTAssertEqual(added.invalidPaths, [expectedMessage])
        XCTAssertFalse(added.mutated)

        let removed = await service.removePaths(
            existing: initial,
            paths: [file.path],
            rawPaths: [file.path],
            mode: "codemap_only"
        )
        XCTAssertEqual(removed.selection, initial)
        XCTAssertEqual(removed.invalidPaths, [expectedMessage])
        XCTAssertFalse(removed.mutated)

        let demoted = await service.demotePaths(
            existing: initial,
            paths: [file.path],
            rawPaths: [file.path]
        )
        XCTAssertEqual(demoted.selection, initial)
        XCTAssertEqual(demoted.invalidPaths, [expectedMessage])
        XCTAssertFalse(demoted.mutated)
    }

    func testStoredSelectionDiscardsLegacyCodemapPathKeyAndNeverEmitsIt() throws {
        let legacyJSON = try XCTUnwrap(
            """
            {
              "selectedPaths": ["/workspace/Source.swift"],
              "autoCodemapPaths": ["/workspace/Legacy.swift"],
              "slices": {},
              "codemapAutoEnabled": false
            }
            """.data(using: .utf8)
        )

        let decoded = try JSONDecoder().decode(StoredSelection.self, from: legacyJSON)
        XCTAssertEqual(decoded.selectedPaths, ["/workspace/Source.swift"])
        XCTAssertFalse(decoded.codemapAutoEnabled)

        let encoded = try JSONEncoder().encode(decoded)
        let encodedText = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(encodedText.contains("autoCodemapPaths"))
        XCTAssertFalse(encodedText.contains("/workspace/Legacy.swift"))
    }

    func testSelectionProductionPathContainsNoLegacyRelationshipCalls() throws {
        let repoRoot = try RepoRoot.url()
        let sourceDirectories = [
            "Sources/RepoPrompt/Infrastructure/WorkspaceContext/Selection",
            "Sources/RepoPrompt/Features/WorkspaceFiles"
        ]
        let forbiddenCalls = [
            "codemapFileAPIAggregate(",
            "CodeMapExtractor.resolveReferencedFilePaths(",
            "CodeMapExtractor.getAutoReferencedAPIs("
        ]
        var violations: [String] = []

        for directory in sourceDirectories {
            let directoryURL = repoRoot.appendingPathComponent(directory, isDirectory: true)
            let enumerator = try XCTUnwrap(
                FileManager.default.enumerator(
                    at: directoryURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
            )
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                for call in forbiddenCalls where contents.contains(call) {
                    violations.append("\(RepoRoot.relativePath(for: fileURL, relativeTo: repoRoot)): \(call)")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Selection production paths must not call legacy codemap relationship APIs:\n\(violations.joined(separator: "\n"))"
        )
    }

    private func makeRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceSelectionAutoCodemapInvariantTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
