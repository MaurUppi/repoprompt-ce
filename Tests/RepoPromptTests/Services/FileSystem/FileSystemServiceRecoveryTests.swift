import CoreServices
@testable import RepoPrompt
import XCTest

final class FileSystemServiceRecoveryTests: XCTestCase {
    private var temporaryRoots = FileSystemTemporaryRoots()

    override func tearDownWithError() throws {
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testTempRootCreateEditReadExistsAndModificationDate() async throws {
        let root = try temporaryRoots.makeRoot(suiteName: "FileSystemServiceRecovery")
        let service = try await FileSystemService(
            path: root.path,
            respectGitignore: false,
            respectRepoIgnore: false,
            respectCursorignore: false,
            skipSymlinks: true
        )

        try await service.createFile(atRelativePath: "src/Note.txt", content: "first")
        let existsAfterCreate = await service.fileExistsOnDisk(relativePath: "src/../src/Note.txt")
        let contentAfterCreate = try await service.loadContent(ofRelativePath: "src/./Note.txt")
        XCTAssertTrue(existsAfterCreate)
        XCTAssertEqual(contentAfterCreate, "first")

        try await service.editFile(atRelativePath: "src/Note.txt", newContent: "second")
        let loaded = try await service.loadContentWithDate(ofRelativePath: "src/Note.txt")
        XCTAssertEqual(loaded.content, "second")
        XCTAssertGreaterThan(loaded.modificationDate.timeIntervalSince1970, 0)
    }

    #if DEBUG
        func testFolderScanCapSchedulesQuietFollowUpBatchesThroughAcceptedWatermark() async throws {
            let root = try temporaryRoots.makeRoot(suiteName: "FileSystemFolderScanCap")
            let folders = ["A", "B", "C"]
            for folder in folders {
                let folderURL = root.appendingPathComponent(folder, isDirectory: true)
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                try "new".write(
                    to: folderURL.appendingPathComponent("new.txt"),
                    atomically: true,
                    encoding: .utf8
                )
            }

            let service = try await FileSystemService(
                path: root.path,
                respectGitignore: false,
                respectRepoIgnore: false,
                respectCursorignore: false,
                skipSymlinks: true,
                enableHierarchicalIgnores: false,
                testVisitedPaths: Set(folders),
                testVisitedItems: Dictionary(uniqueKeysWithValues: folders.map { ($0, true) }),
                isTestMode: true,
                maxFoldersPerBatchOverride: 2
            )
            let flags = FSEventStreamEventFlags(
                kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsFile
            )
            let watermarkValue = await service.acceptWatcherPayloadForTesting(folders.map { folder in
                (
                    absolutePath: root.appendingPathComponent("\(folder)/new.txt").path,
                    flags: flags,
                    eventId: 1
                )
            })
            let watermark = try XCTUnwrap(watermarkValue)

            _ = await service.flushPendingEventsNow(throughAcceptedWatcherWatermark: watermark)

            let processed = await service.getProcessedFolders()
            let state = await service.getCoalescingState()
            let publication = await service.publicationStateForTesting()
            XCTAssertEqual(processed, Set(folders))
            XCTAssertTrue(state.pendingScanTargets.isEmpty)
            XCTAssertEqual(
                state.lastScannedEventIdByFolder,
                Dictionary(uniqueKeysWithValues: folders.map { ($0, FSEventStreamEventId(1)) })
            )
            XCTAssertEqual(publication.lastPublishedWatcherAcceptedWatermark, watermark)
        }
    #endif
}
