@testable import RepoPrompt
import XCTest

final class WorkspaceProjectedPathSearchTests: XCTestCase {
    private typealias Support = WorkspaceRootSeedTestSupport

    func testProjectedMatcherExactlyMatchesFullTargetIndexAcrossQueriesAndLimits() throws {
        let root = WorkspaceRootRecord(
            name: "Projected Root",
            fullPath: "/tmp/Projected Root",
            kind: .sessionWorktree
        )
        let snapshot = Support.snapshot(paths: [
            ("A.swift", "100644"),
            ("Deleted.swift", "100644"),
            ("Old.swift", "100644"),
            ("Sources/Space Target.swift", "100644"),
            ("Sources/Ångström.swift", "100644"),
            ("Sources/line\nbreak.swift", "100644")
        ])
        let finalPaths = [
            "A.swift", "Added 文件.swift", "Renamed.swift", "Sources/Space Target.swift",
            "Sources/Ångström.swift", "Sources/line\nbreak.swift"
        ]
        let entries = makeEntries(paths: finalPaths, root: root)
        let plan = WorkspaceRootSeedPlan(
            snapshotIdentity: snapshot.identity,
            targetTreeOID: Support.oid("f"),
            relativeFilePaths: Set(finalPaths),
            relativeFolderPaths: ["Sources"],
            baseRelativeFilePaths: Set(snapshot.searchBase.relativePaths),
            changedRelativeFilePaths: ["Added 文件.swift", "Deleted.swift", "Old.swift", "Renamed.swift"],
            tombstonedBaseRelativeFilePaths: ["Deleted.swift", "Old.swift"],
            verifiedPathCount: 4
        )
        let projected = try XCTUnwrap(WorkspaceProjectedPathSearchIndex(
            snapshot: snapshot,
            plan: plan,
            root: root,
            authoritativeEntries: entries
        ))
        let full = WorkspaceSearchRootPathIndex(
            identity: WorkspaceSearchRootPathIndexIdentity(
                rootID: root.id,
                lifetimeID: UUID(),
                topologyGeneration: 0
            ),
            rootPath: root.standardizedFullPath,
            entries: entries
        )

        let queries = [
            "A", "*.swift", "Space Target", "Projected Root", root.standardizedFullPath,
            "Ångström", "文件", "line\nbreak", "Sources *.swift"
        ]
        for query in queries {
            for limit in [0, 1, 3, 100] {
                let expected = full.search(query, limit: limit)
                let actual = projected.search(query, limit: limit)
                XCTAssertEqual(actual.map(\.entry.id), expected.map(\.entry.id), "query=\(query) limit=\(limit)")
                XCTAssertEqual(actual.map(\.score), expected.map(\.score), "query=\(query) limit=\(limit)")
                XCTAssertEqual(actual.map(\.tieBreakKey), expected.map(\.tieBreakKey), "query=\(query) limit=\(limit)")
            }
        }
        XCTAssertEqual(projected.overlayEntryCount, 2)
        XCTAssertEqual(projected.tombstoneCount, 2)
    }

    func testProjectionThresholdAndCrossRootIsolation() throws {
        let root = WorkspaceRootRecord(name: "Target", fullPath: "/tmp/Target", kind: .sessionWorktree)
        let paths = (0 ..< 40).map { "File\($0).swift" }
        let snapshot = Support.snapshot(paths: paths.map { ($0, "100644") })
        let entries = makeEntries(paths: paths, root: root)

        func plan(changedCount: Int) -> WorkspaceRootSeedPlan {
            WorkspaceRootSeedPlan(
                snapshotIdentity: snapshot.identity,
                targetTreeOID: Support.oid("f"),
                relativeFilePaths: Set(paths),
                relativeFolderPaths: [],
                baseRelativeFilePaths: Set(paths),
                changedRelativeFilePaths: Set(paths.prefix(changedCount)),
                tombstonedBaseRelativeFilePaths: [],
                verifiedPathCount: changedCount
            )
        }

        let retained = try XCTUnwrap(WorkspaceProjectedPathSearchIndex(
            snapshot: snapshot,
            plan: plan(changedCount: 31),
            root: root,
            authoritativeEntries: entries
        ))
        XCTAssertEqual(retained.overlayEntryCount, 31)
        XCTAssertNil(WorkspaceProjectedPathSearchIndex(
            snapshot: snapshot,
            plan: plan(changedCount: 32),
            root: root,
            authoritativeEntries: entries
        ))

        XCTAssertTrue(retained.search("/tmp/OtherRoot", limit: 100).isEmpty)
        XCTAssertTrue(retained.search("OtherRoot/File1", limit: 100).isEmpty)
        XCTAssertEqual(
            retained.search(root.standardizedFullPath, limit: 100).map(\.entry.rootID),
            Array(repeating: root.id, count: paths.count)
        )
    }

    func testProjectedMatcherUsesBoundedTopKStorageAndReusableScratch() async {
        let paths = (0 ..< 20000).map { index in
            index == 1 ? "A\u{1}.swift" : String(format: "Sources/%05d Target.swift", index)
        } + ["A.swift", "A\nbreak.swift"]
        let displayPrefix = "Large Root/"
        let absolutePrefix = "/tmp/Large Root/"
        let relative = PathSearchIndex(paths: paths)
        let full = PathSearchIndex(paths: paths.map {
            displayPrefix + $0 + "\n" + absolutePrefix + $0
        })

        let outcome = await relative.searchProjected(
            "*.swift",
            displayPrefix: displayPrefix,
            absolutePrefix: absolutePrefix,
            limit: 7
        )
        guard case let .completed(candidates, diagnostics) = outcome else {
            return XCTFail("Projected search unexpectedly cancelled")
        }
        let expected = full.searchSynchronously("*.swift", limit: 7)
        XCTAssertEqual(candidates.map(\.tieBreakKey), expected.map(\.tieBreakKey))
        XCTAssertEqual(diagnostics.examinedCount, paths.count)
        XCTAssertEqual(diagnostics.heapPeakCount, 7)
        XCTAssertLessThanOrEqual(diagnostics.heapComparisonCount, paths.count * 16)
        let maximumRelativeBytes = paths.map(\.utf8.count).max() ?? 0
        XCTAssertEqual(
            diagnostics.scratchBytes,
            displayPrefix.utf8.count + absolutePrefix.utf8.count + maximumRelativeBytes * 2 + 2
        )
    }

    func testProjectedMatcherCancellationJoinsLargeWorker() async {
        let paths = (0 ..< 50000).map { String(format: "Sources/%05d CancellationTarget.swift", $0) }
        let index = PathSearchIndex(paths: paths)
        let task = Task {
            await index.searchProjected(
                "*CancellationTarget.swift",
                displayPrefix: "Cancellation Root/",
                absolutePrefix: "/tmp/Cancellation Root/",
                limit: 300
            )
        }
        task.cancel()
        let outcome = await task.value
        guard case let .cancelled(diagnostics) = outcome else {
            return XCTFail("Expected cooperative C cancellation")
        }
        XCTAssertLessThan(diagnostics.examinedCount, paths.count)
        XCTAssertLessThanOrEqual(diagnostics.heapPeakCount, 300)
    }

    func testFirstParityMismatchAtomicallyDisablesRetainedShadow() async throws {
        WorktreeStartupInstrumentation.resetForTesting()
        let root = WorkspaceRootRecord(name: "Isolated", fullPath: "/tmp/Isolated", kind: .sessionWorktree)
        let snapshot = Support.snapshot(paths: [("A.swift", "100644")])
        let projectedEntries = makeEntries(paths: ["A.swift"], root: root)
        let authoritativeEntries = makeEntries(paths: ["A.swift", "B.swift"], root: root)
        let plan = WorkspaceRootSeedPlan(
            snapshotIdentity: snapshot.identity,
            targetTreeOID: snapshot.compatibilityKey.treeOID,
            relativeFilePaths: ["A.swift"],
            relativeFolderPaths: [],
            baseRelativeFilePaths: ["A.swift"],
            changedRelativeFilePaths: [],
            tombstonedBaseRelativeFilePaths: [],
            verifiedPathCount: 0
        )
        let projection = try XCTUnwrap(WorkspaceProjectedPathSearchIndex(
            snapshot: snapshot,
            plan: plan,
            root: root,
            authoritativeEntries: projectedEntries
        ))
        let token = WorkspaceSessionWorktreeOwnershipToken(ownerID: UUID(), generation: 1)
        let scope = WorkspaceRootSeedShadowScope(
            token: token,
            bindingFingerprint: "binding",
            rootID: root.id,
            lifetimeID: UUID(),
            standardizedPhysicalPath: root.standardizedFullPath,
            catalogGeneration: 1,
            appliedIndexGeneration: 0
        )
        let control = WorkspaceProjectedPathSearchShadowControl(scope: scope, projection: projection)
        let index = WorkspaceSearchRootPathIndex(
            identity: .init(rootID: root.id, lifetimeID: scope.lifetimeID, topologyGeneration: 1),
            rootPath: root.standardizedFullPath,
            entries: authoritativeEntries,
            shadowControl: control
        )

        async let first = index.searchVerifyingShadow("*.swift", limit: 10)
        async let second = index.searchVerifyingShadow("*.swift", limit: 10)
        _ = await (first, second)
        XCTAssertFalse(control.isActive)
        XCTAssertEqual(WorktreeStartupInstrumentation.snapshot().shadow.projectedSearchComparisons, 1)

        _ = await index.searchVerifyingShadow("*.swift", limit: 10)
        XCTAssertEqual(WorktreeStartupInstrumentation.snapshot().shadow.projectedSearchComparisons, 1)
    }

    private func makeEntries(
        paths: [String],
        root: WorkspaceRootRecord
    ) -> [WorkspaceSearchCatalogEntry] {
        paths.map { relativePath in
            let file = WorkspaceFileRecord(
                rootID: root.id,
                name: (relativePath as NSString).lastPathComponent,
                relativePath: relativePath,
                fullPath: root.standardizedFullPath + "/" + relativePath,
                parentFolderID: nil
            )
            return WorkspaceSearchCatalogEntry(file: file, root: root)
        }.sorted(by: WorkspaceFileContextStore.searchCatalogEntryPrecedes)
    }
}
