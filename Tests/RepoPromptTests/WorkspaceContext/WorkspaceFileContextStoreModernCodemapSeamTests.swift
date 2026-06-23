import Darwin
import Foundation
@testable import RepoPrompt
import XCTest

final class WorkspaceFileContextStoreModernCodemapSeamTests: XCTestCase {
    func testRootLoadSearchAndReadDoNotInvokeModernCodemapRuntimeProvider() async throws {
        let sandbox = try ModernCodemapStoreFixture.makeSandbox(name: #function)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let root = sandbox.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.write("struct Feature {}\n", to: root.appendingPathComponent("Sources/Feature.swift"))

        let providerInvocations = ModernCodemapLockedCounter()
        let store = WorkspaceFileContextStore(codemapRuntimeProvider: {
            providerInvocations.increment()
            throw WorkspaceCodemapBindingEngineProviderError.unconfigured
        })

        let loaded = try await store.loadRoot(path: root.path)
        let snapshot = await store.searchCatalogSnapshot(rootScope: .visibleWorkspace)
        let search = WorkspaceSearchService()
        _ = await search.rebuildIndex(from: snapshot)
        let searchResult = await search.search("Feature", limit: 10)
        let content = try await store.readContent(
            rootID: loaded.id,
            relativePath: "Sources/Feature.swift"
        )

        XCTAssertEqual(snapshot.files.map(\.standardizedRelativePath), ["Sources/Feature.swift"])
        XCTAssertEqual(searchResult.results.map(\.standardizedRelativePath), ["Sources/Feature.swift"])
        XCTAssertEqual(content, "struct Feature {}\n")
        XCTAssertEqual(providerInvocations.value, 0)
        await store.unloadRoot(id: loaded.id)
        XCTAssertEqual(providerInvocations.value, 0)
    }

    func testFirstExplicitDemandReturnsStableExactRootPendingTicketAndRegistersOnce() async throws {
        let gate = ModernCodemapResolutionGate()
        let fixture = try ModernCodemapStoreFixture(name: #function, resolutionGate: gate)
        addTeardownBlock {
            await gate.release()
            await fixture.shutdown()
        }
        let root = try fixture.makePlainRoot(files: [
            "Sources/Feature.swift": "struct Feature {}\n"
        ])
        let store = fixture.makeStore()
        let loaded = try await store.loadRoot(path: root.path)
        let loadedFiles = await store.files(inRoot: loaded.id)
        let file = try XCTUnwrap(loadedFiles.first)

        let firstTicket = try await pendingTicket(
            store.requestCodemapArtifact(forFileID: file.id)
        )
        let duplicateTicket = try await pendingTicket(
            store.requestCodemapArtifact(forFileID: file.id)
        )
        XCTAssertEqual(firstTicket, duplicateTicket)
        let gateEntered = await gate.waitUntilEntered()
        XCTAssertTrue(gateEntered)

        let candidate = await fixture.registry.makeBindingCatalogClient()
            .resolveManifestBinding(firstTicket.rootEpoch, file.standardizedRelativePath)
        XCTAssertEqual(candidate?.identity.fileID, file.id)
        XCTAssertEqual(candidate?.identity.rootID, loaded.id)
        XCTAssertEqual(candidate?.identity.rootLifetimeID, firstTicket.rootEpoch.rootLifetimeID)
        XCTAssertEqual(fixture.providerAccessCount.value, 1)
        XCTAssertEqual(fixture.runtimeFactoryCount.value, 1)
        XCTAssertEqual(fixture.engineFactoryCount.value, 1)
        let resolutionCount = await gate.resolutionCount
        XCTAssertEqual(resolutionCount, 1)

        await gate.release()
        let settled = try await settledResult(store: store, ticket: firstTicket)
        assertNonGitTerminal(settled)
        await store.unloadRoot(id: loaded.id)
    }

    func testNonGitDemandBecomesTerminalWithoutSourceReadManifestBuildOrGraphWork() async throws {
        let fixture = try ModernCodemapStoreFixture(name: #function)
        addTeardownBlock { await fixture.shutdown() }
        let root = try fixture.makePlainRoot(files: [
            "Sources/Feature.swift": "struct Feature {}\n"
        ])
        let store = fixture.makeStore()
        let loaded = try await store.loadRoot(path: root.path)
        let loadedFiles = await store.files(inRoot: loaded.id)
        let file = try XCTUnwrap(loadedFiles.first)
        let ticket = try await pendingTicket(
            store.requestCodemapArtifact(forFileID: file.id)
        )

        let settled = try await settledResult(store: store, ticket: ticket)
        assertNonGitTerminal(settled)
        let runtime = try fixture.runtime()
        let engine = try runtime.bindingEngine()
        let accounting = await engine.accounting()
        let coordinator = await runtime.coordinator.accounting()

        XCTAssertEqual(accounting.counters.capabilityResolutions, 1)
        XCTAssertEqual(accounting.counters.classifications, 0)
        XCTAssertEqual(accounting.counters.validatedWorktreeReads, 0)
        XCTAssertEqual(accounting.counters.builds, 0)
        XCTAssertEqual(accounting.counters.manifestLoads, 0)
        XCTAssertEqual(accounting.counters.manifestWrites, 0)
        XCTAssertEqual(accounting.counters.materializations, 0)
        XCTAssertEqual(fixture.manifestReadCount.value, 0)
        XCTAssertEqual(fixture.buildCount.value, 0)
        XCTAssertEqual(coordinator.counters.requests, 0)
        try assertStoreSourceHasNoGraphPath()

        await store.unloadRoot(id: loaded.id)
    }

    func testCatalogAdvanceFencesPendingTicketAndExactRegistryRoute() async throws {
        let gate = ModernCodemapResolutionGate()
        let fixture = try ModernCodemapStoreFixture(name: #function, resolutionGate: gate)
        addTeardownBlock {
            await gate.release()
            await fixture.shutdown()
        }
        let root = try fixture.makePlainRoot(files: [
            "Sources/Feature.swift": "struct Feature {}\n"
        ])
        let store = fixture.makeStore()
        let loaded = try await store.loadRoot(path: root.path)
        let loadedFiles = await store.files(inRoot: loaded.id)
        let file = try XCTUnwrap(loadedFiles.first)
        let ticket = try await pendingTicket(
            store.requestCodemapArtifact(forFileID: file.id)
        )
        let gateEntered = await gate.waitUntilEntered()
        XCTAssertTrue(gateEntered)

        let routed = await fixture.registry.makeBindingCatalogClient()
            .resolveManifestBinding(ticket.rootEpoch, file.standardizedRelativePath)
        XCTAssertEqual(routed?.identity.fileID, file.id)

        try Self.write("struct Added {}\n", to: root.appendingPathComponent("Sources/Added.swift"))
        await store.replayObservedFileSystemDeltas(
            rootID: loaded.id,
            deltas: [.fileAdded("Sources/Added.swift")]
        )

        await assertStale(store.codemapArtifactDemandStatus(ticket))
        let routeUnavailable = await routeBecomesUnavailable(
            registry: fixture.registry,
            ticket: ticket,
            relativePath: file.standardizedRelativePath
        )
        XCTAssertTrue(routeUnavailable)
        await gate.release()
        let engineRootCountIsZero = try await engineRootCountBecomesZero(fixture: fixture)
        XCTAssertTrue(engineRootCountIsZero)
        await store.unloadRoot(id: loaded.id)
    }

    func testUnloadAndReloadFenceOldLifetimeAndDrainModernRootState() async throws {
        let gate = ModernCodemapResolutionGate()
        let fixture = try ModernCodemapStoreFixture(name: #function, resolutionGate: gate)
        addTeardownBlock {
            await gate.release()
            await fixture.shutdown()
        }
        let root = try fixture.makePlainRoot(files: [
            "Sources/Feature.swift": "struct Feature {}\n"
        ])
        let store = fixture.makeStore()
        let firstRoot = try await store.loadRoot(path: root.path)
        let firstFiles = await store.files(inRoot: firstRoot.id)
        let firstFile = try XCTUnwrap(firstFiles.first)
        let firstTicket = try await pendingTicket(
            store.requestCodemapArtifact(forFileID: firstFile.id)
        )
        let gateEntered = await gate.waitUntilEntered()
        XCTAssertTrue(gateEntered)

        let unloadTask = Task {
            await store.unloadRoot(id: firstRoot.id)
        }
        let routeUnavailable = await routeBecomesUnavailable(
            registry: fixture.registry,
            ticket: firstTicket,
            relativePath: firstFile.standardizedRelativePath
        )
        XCTAssertTrue(routeUnavailable)
        await assertStale(store.codemapArtifactDemandStatus(firstTicket))
        await gate.release()
        await unloadTask.value

        let secondRoot = try await store.loadRoot(path: root.path)
        let secondFiles = await store.files(inRoot: secondRoot.id)
        let secondFile = try XCTUnwrap(secondFiles.first)
        let secondTicket = try await pendingTicket(
            store.requestCodemapArtifact(forFileID: secondFile.id)
        )

        XCTAssertNotEqual(secondRoot.id, firstRoot.id)
        XCTAssertNotEqual(secondTicket.rootEpoch, firstTicket.rootEpoch)
        await assertStale(store.codemapArtifactDemandStatus(firstTicket))
        try await assertNonGitTerminal(settledResult(store: store, ticket: secondTicket))
        await store.unloadRoot(id: secondRoot.id)
        let engineRootCountIsZero = try await engineRootCountBecomesZero(fixture: fixture)
        XCTAssertTrue(engineRootCountIsZero)
    }

    func testReadyDemandsReuseInjectedRuntimeRegistryAndEngineSingletons() async throws {
        let repositoryFixture = try ReviewGitRepositoryFixture(name: #function)
        let root = try repositoryFixture.makeRepository(
            named: "repository",
            files: [
                "Sources/First.swift": "struct First {}\n",
                "Sources/Second.swift": "struct Second {}\n"
            ]
        )
        let fixture = try ModernCodemapStoreFixture(name: #function)
        addTeardownBlock {
            await fixture.shutdown()
            repositoryFixture.cleanup()
        }
        let store = fixture.makeStore()
        let loaded = try await store.loadRoot(path: root.path)
        let files = await store.files(inRoot: loaded.id)
        let firstFile = try XCTUnwrap(files.first {
            $0.standardizedRelativePath == "Sources/First.swift"
        })
        let secondFile = try XCTUnwrap(files.first {
            $0.standardizedRelativePath == "Sources/Second.swift"
        })

        let firstTicket = try await pendingTicket(
            store.requestCodemapArtifact(forFileID: firstFile.id)
        )
        let firstReady = try await readyResult(
            settledResult(store: store, ticket: firstTicket)
        )
        let secondTicket = try await pendingTicket(
            store.requestCodemapArtifact(forFileID: secondFile.id)
        )
        let secondReady = try await readyResult(
            settledResult(store: store, ticket: secondTicket)
        )

        XCTAssertEqual(firstTicket.rootEpoch, secondTicket.rootEpoch)
        XCTAssertEqual(firstReady.identity.fileID, firstFile.id)
        XCTAssertEqual(firstReady.snapshot.fileID, firstFile.id)
        XCTAssertEqual(try firstReady.handle.artifactKey(), firstReady.snapshot.artifactKey)
        XCTAssertEqual(secondReady.identity.fileID, secondFile.id)
        XCTAssertEqual(secondReady.snapshot.fileID, secondFile.id)
        XCTAssertEqual(try secondReady.handle.artifactKey(), secondReady.snapshot.artifactKey)
        XCTAssertEqual(fixture.providerAccessCount.value, 1)
        XCTAssertEqual(fixture.runtimeFactoryCount.value, 1)
        XCTAssertEqual(fixture.engineFactoryCount.value, 1)
        XCTAssertTrue(try fixture.runtime().bindingIntegrationRegistry === fixture.registry)

        let firstCandidate = await fixture.registry.makeBindingCatalogClient()
            .resolveManifestBinding(
                firstTicket.rootEpoch,
                firstFile.standardizedRelativePath
            )
        let secondCandidate = await fixture.registry.makeBindingCatalogClient()
            .resolveManifestBinding(
                secondTicket.rootEpoch,
                secondFile.standardizedRelativePath
            )
        XCTAssertEqual(firstCandidate?.identity.fileID, firstFile.id)
        XCTAssertEqual(secondCandidate?.identity.fileID, secondFile.id)

        await store.unloadRoot(id: loaded.id)
        XCTAssertThrowsError(try firstReady.handle.artifactKey()) {
            XCTAssertEqual($0 as? WorkspaceCodemapLiveOverlayBundleAccessError, .closed)
        }
        XCTAssertThrowsError(try secondReady.handle.artifactKey()) {
            XCTAssertEqual($0 as? WorkspaceCodemapLiveOverlayBundleAccessError, .closed)
        }
    }

    func testCancellationAfterReadyRevokesRetainedHandleIdempotently() async throws {
        let repositoryFixture = try ReviewGitRepositoryFixture(name: #function)
        let root = try repositoryFixture.makeRepository(
            named: "repository",
            files: ["Sources/Feature.swift": "struct Feature {}\n"]
        )
        let fixture = try ModernCodemapStoreFixture(name: #function)
        addTeardownBlock {
            await fixture.shutdown()
            repositoryFixture.cleanup()
        }
        let store = fixture.makeStore()
        let loaded = try await store.loadRoot(path: root.path)
        let files = await store.files(inRoot: loaded.id)
        let file = try XCTUnwrap(files.first)
        let ticket = try await pendingTicket(
            store.requestCodemapArtifact(forFileID: file.id)
        )
        let ready = try await readyResult(
            settledResult(store: store, ticket: ticket)
        )
        let runtime = try fixture.runtime()
        let accountingBeforeCancellation = await runtime.artifactStore.accounting()
        XCTAssertEqual(accountingBeforeCancellation.activeLeaseCount, 1)
        XCTAssertGreaterThan(accountingBeforeCancellation.activeLeaseBytes, 0)

        let firstCancellation = await store.cancelCodemapArtifactDemand(ticket)
        XCTAssertTrue(firstCancellation)
        await assertCancelled(store.codemapArtifactDemandStatus(ticket))
        XCTAssertThrowsError(try ready.handle.artifactKey()) {
            XCTAssertEqual($0 as? WorkspaceCodemapLiveOverlayBundleAccessError, .closed)
        }
        let accountingAfterFirstCancellation = await runtime.artifactStore.accounting()
        XCTAssertEqual(accountingAfterFirstCancellation.activeLeaseCount, 1)
        XCTAssertEqual(
            accountingAfterFirstCancellation.activeLeaseBytes,
            accountingBeforeCancellation.activeLeaseBytes
        )

        let secondCancellation = await store.cancelCodemapArtifactDemand(ticket)
        XCTAssertTrue(secondCancellation)
        await assertCancelled(store.codemapArtifactDemandStatus(ticket))
        XCTAssertThrowsError(try ready.handle.artifactKey()) {
            XCTAssertEqual($0 as? WorkspaceCodemapLiveOverlayBundleAccessError, .closed)
        }
        let accountingAfterSecondCancellation = await runtime.artifactStore.accounting()
        XCTAssertEqual(accountingAfterSecondCancellation.activeLeaseCount, 1)
        XCTAssertEqual(
            accountingAfterSecondCancellation.activeLeaseBytes,
            accountingBeforeCancellation.activeLeaseBytes
        )

        await store.unloadRoot(id: loaded.id)
    }

    func testReadyCancellationCleanupCannotCancelSamePathSuccessor() async throws {
        let repositoryFixture = try ReviewGitRepositoryFixture(name: #function)
        let root = try repositoryFixture.makeRepository(
            named: "repository",
            files: ["Sources/Feature.swift": "struct Feature {}\n"]
        )
        let fixture = try ModernCodemapStoreFixture(name: #function)
        let cancellationGate = ModernCodemapSuspensionGate()
        let successorPublicationGate = ModernCodemapArmableSuspensionGate()
        addTeardownBlock {
            await cancellationGate.release()
            await successorPublicationGate.release()
            await fixture.shutdown()
            repositoryFixture.cleanup()
        }
        let store = fixture.makeStore(
            cancellationCleanupHook: { _ in
                await cancellationGate.enterAndWait()
            },
            readyPublicationHook: { _ in
                await successorPublicationGate.enterIfArmedAndWait()
            }
        )
        let loaded = try await store.loadRoot(path: root.path)
        let files = await store.files(inRoot: loaded.id)
        let file = try XCTUnwrap(files.first)
        let cancelledTicket = try await pendingTicket(
            store.requestCodemapArtifact(forFileID: file.id)
        )
        let cancelledReady = try await readyResult(
            settledResult(store: store, ticket: cancelledTicket)
        )
        await successorPublicationGate.arm()

        let cancellationTask = Task {
            await store.cancelCodemapArtifactDemand(cancelledTicket)
        }
        let cancellationEntered = await cancellationGate.waitUntilEntered()
        XCTAssertTrue(cancellationEntered)
        await assertCancelled(store.codemapArtifactDemandStatus(cancelledTicket))
        XCTAssertThrowsError(try cancelledReady.handle.artifactKey()) {
            XCTAssertEqual($0 as? WorkspaceCodemapLiveOverlayBundleAccessError, .closed)
        }

        let successorTicket = try await pendingTicket(
            store.requestCodemapArtifact(forFileID: file.id)
        )
        XCTAssertNotEqual(successorTicket, cancelledTicket)
        let successorPublicationEntered = await successorPublicationGate.waitUntilEntered()
        XCTAssertTrue(successorPublicationEntered)

        await cancellationGate.release()
        let cancellationResult = await cancellationTask.value
        XCTAssertTrue(cancellationResult)
        await successorPublicationGate.release()
        let successorReady = try await readyResult(
            settledResult(store: store, ticket: successorTicket)
        )
        XCTAssertEqual(successorReady.ticket, successorTicket)
        XCTAssertEqual(try successorReady.handle.artifactKey(), successorReady.snapshot.artifactKey)

        await store.unloadRoot(id: loaded.id)
    }

    private func pendingTicket(
        _ result: WorkspaceCodemapArtifactDemandResult
    ) throws -> WorkspaceCodemapArtifactDemandTicket {
        guard case let .pending(ticket) = result else {
            throw ModernCodemapStoreTestError.expectedPending
        }
        return ticket
    }

    private func readyResult(
        _ result: WorkspaceCodemapArtifactDemandResult
    ) throws -> WorkspaceCodemapArtifactDemandReady {
        guard case let .ready(ready) = result else {
            throw ModernCodemapStoreTestError.expectedReady
        }
        return ready
    }

    private func settledResult(
        store: WorkspaceFileContextStore,
        ticket: WorkspaceCodemapArtifactDemandTicket,
        timeout: Duration = .seconds(15)
    ) async throws -> WorkspaceCodemapArtifactDemandResult {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            let result = await store.codemapArtifactDemandStatus(ticket)
            if case .pending = result {
                try await Task.sleep(for: .milliseconds(10))
                continue
            }
            return result
        }
        throw ModernCodemapStoreTestError.timedOut
    }

    private func routeBecomesUnavailable(
        registry: WorkspaceCodemapBindingIntegrationRegistry,
        ticket: WorkspaceCodemapArtifactDemandTicket,
        relativePath: String
    ) async -> Bool {
        for _ in 0 ..< 500 {
            let candidate = await registry.makeBindingCatalogClient()
                .resolveManifestBinding(ticket.rootEpoch, relativePath)
            if candidate == nil { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func engineRootCountBecomesZero(
        fixture: ModernCodemapStoreFixture
    ) async throws -> Bool {
        let engine = try fixture.runtime().bindingEngine()
        for _ in 0 ..< 500 {
            if await engine.accounting().rootCount == 0 { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return await engine.accounting().rootCount == 0
    }

    private func assertNonGitTerminal(
        _ result: WorkspaceCodemapArtifactDemandResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unavailable(.gitTerminal(.nonGit)) = result else {
            return XCTFail("Expected terminal non-Git unavailability.", file: file, line: line)
        }
    }

    private func assertCancelled(
        _ result: WorkspaceCodemapArtifactDemandResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unavailable(.cancelled) = result else {
            return XCTFail("Expected cancelled unavailability.", file: file, line: line)
        }
    }

    private func assertStoreSourceHasNoGraphPath(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var repositoryRoot = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 {
            repositoryRoot.deleteLastPathComponent()
        }
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/RepoPrompt/Infrastructure/WorkspaceContext/WorkspaceFileContextStore.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertNil(
            source.range(of: "graph", options: .caseInsensitive),
            "WorkspaceFileContextStore must not contain a graph actor, factory, or construction path in this slice.",
            file: file,
            line: line
        )
    }

    private func assertStale(
        _ result: WorkspaceCodemapArtifactDemandResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unavailable(.staleCurrentness) = result else {
            return XCTFail("Expected stale currentness.", file: file, line: line)
        }
    }

    private static func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

private enum ModernCodemapStoreTestError: Error {
    case expectedPending
    case expectedReady
    case timedOut
}

private final class ModernCodemapStoreFixture: @unchecked Sendable {
    let registry = WorkspaceCodemapBindingIntegrationRegistry()
    let providerAccessCount = ModernCodemapLockedCounter()
    let runtimeFactoryCount = ModernCodemapLockedCounter()
    let engineFactoryCount = ModernCodemapLockedCounter()
    let manifestReadCount = ModernCodemapLockedCounter()
    let buildCount = ModernCodemapLockedCounter()

    private let sandbox: URL
    private let runtimeProvider: CodeMapArtifactRuntimeProvider

    init(name: String, resolutionGate: ModernCodemapResolutionGate? = nil) throws {
        let sandbox = try Self.makeSandbox(name: name)
        let artifactRoot = try Self.makeSecureDirectory(in: sandbox, named: "artifacts")
        let registry = registry
        let runtimeFactoryCount = runtimeFactoryCount
        let engineFactoryCount = engineFactoryCount
        let manifestReadCount = manifestReadCount
        let buildCount = buildCount
        let defaultBuilder = CodeMapArtifactBuilderClient()
        runtimeProvider = CodeMapArtifactRuntimeProvider {
            runtimeFactoryCount.increment()
            return try CodeMapArtifactRuntime(
                rootURL: artifactRoot,
                manifestStoreHooks: CodeMapRootManifestStoreHooks(
                    afterReadAdmission: {
                        manifestReadCount.increment()
                    }
                ),
                builder: CodeMapArtifactBuilderClient(execute: { input, ownerID, priority in
                    buildCount.increment()
                    return try await defaultBuilder.execute(input, ownerID, priority)
                }),
                bindingIntegrationRegistry: registry,
                bindingEngineFactory: { runtime in
                    engineFactoryCount.increment()
                    return WorkspaceCodemapBindingEngine(
                        runtime: runtime,
                        capabilityService: WorkspaceCodemapGitCapabilityService(
                            namespaceSalt: Data(
                                repeating: 0x6C,
                                count: GitBlobRepositoryNamespace.saltByteCount
                            ),
                            hooks: WorkspaceCodemapGitCapabilityServiceHooks(
                                beforeResolution: {
                                    await resolutionGate?.enterAndWait()
                                }
                            )
                        ),
                        sourceReader: registry.makeValidatedSourceReaderClient(),
                        catalogClient: registry.makeBindingCatalogClient()
                    )
                }
            )
        }
        self.sandbox = sandbox
    }

    deinit {
        try? FileManager.default.removeItem(at: sandbox)
    }

    func makeStore(
        cancellationCleanupHook: @escaping @Sendable (
            WorkspaceCodemapArtifactDemandTicket
        ) async -> Void = { _ in },
        readyPublicationHook: @escaping @Sendable (
            WorkspaceCodemapArtifactDemandTicket
        ) async -> Void = { _ in }
    ) -> WorkspaceFileContextStore {
        let providerAccessCount = providerAccessCount
        let runtimeProvider = runtimeProvider
        return WorkspaceFileContextStore(
            codemapRuntimeProvider: {
                providerAccessCount.increment()
                return try runtimeProvider.runtime()
            },
            modernCodemapCancellationCleanupHook: cancellationCleanupHook,
            modernCodemapReadyPublicationHook: readyPublicationHook
        )
    }

    func makePlainRoot(files: [String: String]) throws -> URL {
        let root = sandbox.appendingPathComponent(
            "plain-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (relativePath, contents) in files {
            try Self.write(
                contents,
                to: root.appendingPathComponent(relativePath)
            )
        }
        return root
    }

    func runtime() throws -> CodeMapArtifactRuntime {
        try runtimeProvider.runtime()
    }

    func shutdown() async {
        if let runtime = try? runtimeProvider.runtime(),
           let engine = try? runtime.bindingEngine()
        {
            await engine.shutdown()
        }
    }

    static func makeSandbox(name: String) throws -> URL {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WorkspaceFileContextStoreModernCodemapSeamTests-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        return sandbox
    }

    private static func makeSecureDirectory(in parent: URL, named name: String) throws -> URL {
        let directory = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        guard chmod(directory.path, 0o700) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let resolvedPath = try directory.path.withCString { pointer -> String in
            guard let resolved = realpath(pointer, nil) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            defer { free(resolved) }
            return String(cString: resolved)
        }
        return URL(fileURLWithPath: resolvedPath, isDirectory: true)
    }

    private static func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

private final class ModernCodemapLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock { storage += 1 }
    }
}

private actor ModernCodemapSuspensionGate {
    private var entered = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func enterAndWait() async {
        entered = true
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered(timeout: Duration = .seconds(10)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !entered, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return entered
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private actor ModernCodemapArmableSuspensionGate {
    private var armed = false
    private var entered = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func arm() {
        armed = true
    }

    func enterIfArmedAndWait() async {
        guard armed else { return }
        entered = true
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered(timeout: Duration = .seconds(10)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !entered, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return entered
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private actor ModernCodemapResolutionGate {
    private var entered = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var resolutionCount = 0

    func enterAndWait() async {
        resolutionCount += 1
        entered = true
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered(timeout: Duration = .seconds(10)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !entered, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return entered
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
