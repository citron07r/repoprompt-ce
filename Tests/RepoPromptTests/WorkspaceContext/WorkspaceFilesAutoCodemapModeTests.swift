@testable import RepoPrompt
import XCTest

@MainActor
final class WorkspaceFilesAutoCodemapModeTests: XCTestCase {
    func testExplicitCodemapOnlyIntentFailsClosedAndClearsAutomaticProjection() {
        let fixture = makeFixture(fileName: "Present.swift")
        XCTAssertTrue(fixture.viewModel.codemapAutoEnabled)

        fixture.viewModel.setFileAsCodemap(fixture.file)

        XCTAssertFalse(fixture.viewModel.codemapAutoEnabled)
        XCTAssertTrue(fixture.viewModel.autoCodemapFiles.isEmpty)
        XCTAssertFalse(fixture.viewModel.isAutoCodemapFile(fixture.file))
        XCTAssertTrue(fixture.viewModel.snapshotSelection().selectedPaths.isEmpty)
    }

    func testOrdinaryFileRemovalPreservesAutoAndFullClearRestoresIt() async {
        do {
            let fixture = makeFixture(fileName: "Selected.swift")
            fixture.viewModel.selectFileForTesting(fixture.file)
            XCTAssertTrue(fixture.viewModel.codemapAutoEnabled)

            fixture.viewModel.removeFileFromAllSelections(fixture.file)

            XCTAssertTrue(fixture.viewModel.selectedFiles.isEmpty)
            XCTAssertTrue(fixture.viewModel.codemapAutoEnabled)
        }

        do {
            let fixture = makeFixture(fileName: "Clear.swift")
            fixture.viewModel.enterManualCodemapMode()
            XCTAssertFalse(fixture.viewModel.codemapAutoEnabled)

            await fixture.viewModel.clearSelection()

            XCTAssertTrue(fixture.viewModel.selectedFiles.isEmpty)
            XCTAssertTrue(fixture.viewModel.autoCodemapFiles.isEmpty)
            XCTAssertTrue(fixture.viewModel.codemapAutoEnabled)
        }
    }

    func testSnapshotAndEncodingContainNoInferredPathState() throws {
        let fixture = makeFixture(fileName: "Dependency.swift")
        fixture.viewModel.selectFileForTesting(fixture.file)

        let snapshot = fixture.viewModel.snapshotSelection()
        XCTAssertEqual(snapshot.selectedPaths, [fixture.file.standardizedFullPath])
        XCTAssertTrue(snapshot.codemapAutoEnabled)

        let encoded = try JSONEncoder().encode(snapshot)
        let encodedText = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(encodedText.contains("autoCodemapPaths"))

        fixture.viewModel.enterManualCodemapMode()
        XCTAssertFalse(fixture.viewModel.codemapAutoEnabled)
        XCTAssertTrue(fixture.viewModel.autoCodemapFiles.isEmpty)
    }

    func testPublicationRevalidationIsFinalAwaitBeforeSynchronousCommit() throws {
        let repoRoot = try RepoRoot.url()
        let sourceURL = repoRoot.appendingPathComponent(
            "Sources/RepoPrompt/Features/WorkspaceFiles/ViewModels/WorkspaceFilesViewModel.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let revalidation = try XCTUnwrap(try source.range(
            of: "guard automaticCodemapSelectionIsCurrent(",
            range: XCTUnwrap(source.range(
                of: "revalidateAutomaticCodemapSelectionForPublication("
            )).upperBound ..< source.endIndex
        ))
        let commit = try XCTUnwrap(source.range(
            of: "resetAutoCodemapFiles(resolvedTargets)",
            range: revalidation.lowerBound ..< source.endIndex
        ))
        let synchronousCommitRegion = source[revalidation.lowerBound ..< commit.upperBound]
        XCTAssertFalse(synchronousCommitRegion.contains("await"))
    }

    private func makeFixture(fileName: String) -> (
        viewModel: WorkspaceFilesViewModel,
        file: FileViewModel
    ) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceFilesAutoCodemapModeTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let rootID = UUID()
        let file = FileViewModel(
            file: File(
                name: fileName,
                path: rootURL.appendingPathComponent(fileName).path,
                modificationDate: Date(timeIntervalSince1970: 1000)
            ),
            rootPath: rootURL.path,
            rootIdentifier: rootID,
            rootFolderPath: rootURL.path,
            fileSystemService: nil
        )
        return (WorkspaceFilesViewModel(), file)
    }
}
